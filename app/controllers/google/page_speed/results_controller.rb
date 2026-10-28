# encoding: UTF-8

module Google
  module PageSpeed
    # So a slow post, or one real readers find slow, is spotted across the
    # blog at once rather than tested page by page.
    class ResultsController < ApplicationController
      SEARCH_FIELDS = [
        Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. /post/ or css-grid"),
        Filtering::DateRange.new(:tested, field: :fetched_at, label: "Tested")
      ].freeze
      DEVICE_TABS = Filtering::Tabs.new(:device,
        field: :strategy, label: "Filter by device",
        choices: {"mobile" => ["Mobile", "mobile"], "desktop" => ["Desktop", "desktop"]}
      )
      # The slowest first, since they're the ones to fix.
      SORT_COLUMNS = {
        "performance" => "asc", "field_lcp_ms" => "desc", "field_inp_ms" => "desc", "field_cls" => "desc",
        "fetched_at" => "desc", "url" => "asc"
      }.freeze

      def index
        @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: DEVICE_TABS)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :url)
        results = @sorting.apply(@filtering.apply(Result.all))

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(results, params)
            @results = @pagination.records
            @tab_counts = @filtering.tab_counts(Result.all)
            # Searched but not narrowed to a device, since the chart sets the
            # two devices side by side.
            @device_gaps = Result.device_gaps(@filtering.searched(Result.all))
            @lcp_pairs = Result.lcp_pairs(@filtering.searched(Result.all))
            @category_averages = Result.category_averages(@filtering.searched(Result.all))
            @weakest = Result.weakest(@filtering.searched(Result.all))
            @regressions = ResultHistory.regressions(@filtering.searched(ResultHistory.all))
          end
          format.csv do
            send_csv Result.to_csv(results), filename: "pagespeed-#{Date.current.iso8601}.csv"
          end
        end
      end

      def sync
        SyncRequest.enqueue("page_speed", limit: SyncService::DEFAULT_LIMIT)
        redirect_to google_page_speed_results_path,
                    notice: "Testing the #{SyncService::DEFAULT_LIMIT} least recently tested pages in the background. This takes a few minutes."
      end
    end
  end
end
