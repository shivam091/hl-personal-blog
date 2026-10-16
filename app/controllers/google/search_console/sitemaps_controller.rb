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
      def index
        @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: ERROR_TABS)
        # A sitemap Google hasn't read lately is the one worth a look, so the
        # stalest come first.
        sitemaps = @filtering.apply(Sitemap.all).order_by(last_downloaded_at: :asc, path: :asc)

        respond_to do |format|
          format.html do
            @sitemaps = sitemaps.to_a
            @tab_counts = @filtering.tab_counts(Sitemap.all)
            @history = SitemapHistory.daily
            @changes = @sitemaps.to_a.to_h { |sitemap| [sitemap.path, SitemapHistory.changes(sitemap.path)] }
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
