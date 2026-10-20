# encoding: UTF-8

module Google
  module SafeBrowsing
    class LinkChecksController < ApplicationController
      SEARCH_FIELDS = [
        Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. github.com")
      ].freeze
      STATUS_TABS = Filtering::Tabs.new(:status,
        field: :threat_types, label: "Filter by status",
        choices: {"flagged" => ["Flagged", {"$ne" => []}], "safe" => ["Safe", []]}
      )
      SORT_COLUMNS = {"flagged_at" => "desc", "checked_at" => "desc", "url" => "asc"}.freeze

      def index
        @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: STATUS_TABS)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :url)
        checks = @sorting.apply(@filtering.apply(LinkCheck.all))

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(checks, params)
            @checks = @pagination.records
            @tab_counts = @filtering.tab_counts(LinkCheck.all)
            @flagged_count = LinkCheck.flagged.count
          end
          format.csv do
            send_csv LinkCheck.to_csv(checks), filename: "link-safety-#{Date.current.iso8601}.csv"
          end
        end
      end

      def sync
        SyncRequest.enqueue("safe_browsing")
        redirect_to google_safe_browsing_link_checks_path,
                    notice: "Checking outbound links with Safe Browsing in the background. Refresh in a moment to see the results."
      end
    end
  end
end
