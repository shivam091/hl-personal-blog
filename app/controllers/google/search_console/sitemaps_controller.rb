# encoding: UTF-8

module Google
  module SearchConsole
    # So a sitemap Google stopped reading, or found errors in, is noticed
    # without opening Search Console.
    class SitemapsController < ApplicationController
      SEARCH_FIELDS = [
        Filtering::Contains.new(:q, field: :path, label: "Path contains", placeholder: "e.g. sitemap.xml"),
        Filtering::DateRange.new(:downloaded, field: :last_downloaded_at, label: "Last downloaded")
      ].freeze
      ERROR_TABS = Filtering::Tabs.new(:errors,
        field: :error_count,
        label: "Filter by errors",
        choices: {"yes" => ["With errors", {"$gt" => 0}], "no" => ["Without errors", 0]}
      )
      # A sitemap Google hasn't read lately is the one worth a look, so the
      # stalest come first.
      SORT_COLUMNS = {
        "last_downloaded_at" => "asc", "last_submitted_at" => "desc", "path" => "asc",
        "error_count" => "desc", "warning_count" => "desc"
      }.freeze

      def index
        @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: ERROR_TABS)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :path)
        sitemaps = @sorting.apply(@filtering.apply(Sitemap.all))

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(sitemaps, params)
            @sitemaps = @pagination.records
            @tab_counts = @filtering.tab_counts(Sitemap.all)
          end
          format.csv do
            send_csv Sitemap.to_csv(sitemaps), filename: "sitemaps-#{Date.current.iso8601}.csv"
          end
        end
      end

      # For a change that can't wait for the next blog sync to resubmit it.
      def submit
        SyncRequest.enqueue("sitemap_submission")
        redirect_to google_search_console_sitemaps_path,
                    notice: "Submitting the sitemap to Search Console in the background. Refresh in a moment to see it pending."
      end

      # Search Console only keeps each sitemap's latest state, so there's no
      # range of days to choose.
      def sync
        SyncRequest.enqueue("search_console_sitemaps")
        redirect_to google_search_console_sitemaps_path,
                    notice: "Syncing sitemaps from Search Console in the background. Refresh in a moment to see the latest status."
      end
    end
  end
end
