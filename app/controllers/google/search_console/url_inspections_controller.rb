# encoding: UTF-8

module Google
  module SearchConsole
    # So why a page isn't indexed (blocked, a soft 404, another canonical)
    # can be read across the blog at once rather than inspected page by page.
    class UrlInspectionsController < ApplicationController
      SEARCH_FIELDS = [
        Filtering::RelatedContains.new(:q, field: :crawled_page_id, label: "URL contains", model: CrawledPage, model_field: :url,
          placeholder: "e.g. /post/ or css-grid"),
        Filtering::Contains.new(:coverage, field: :coverage_state, label: "Coverage contains", placeholder: "e.g. Crawled or redirect"),
        Filtering::DateRange.new(:crawled, field: :last_crawled_at, label: "Last crawled"),
        Filtering::DateRange.new(:inspected, field: :inspected_at, label: "Inspected"),
        # The quiet reasons a page gets no search traffic, which the verdict
        # alone doesn't show.
        Filtering::Condition.new(:issue, label: "Issue", conditions: {
          "canonical" => ["Google chose another canonical", {
            :google_canonical.nin => [nil, ""], :user_canonical.nin => [nil, ""],
            "$expr" => {"$ne" => ["$google_canonical", "$user_canonical"]}
          }],
          "rich_results" => ["Rich result issues", {:rich_results_verdict.in => %w[FAIL PARTIAL]}],
          "no_rich_results" => ["No rich results detected", {"rich_results.0" => {"$exists" => false}}],
          "no_sitemap" => ["Not in a sitemap", {"sitemaps.0" => {"$exists" => false}}]
        })
      ].freeze
      # Search Console's own verdicts, so a tab means what it does there.
      VERDICT_TABS = Filtering::Tabs.new(:verdict, field: :verdict, label: "Filter by verdict",
        choices: {"pass" => ["Indexed", "PASS"], "neutral" => ["Excluded", "NEUTRAL"], "fail" => ["Error", "FAIL"], "partial" => ["Partial", "PARTIAL"]})
      SORT_COLUMNS = {
        "inspected_at" => "desc", "last_crawled_at" => "desc", "verdict" => "asc", "coverage_state" => "asc"
      }.freeze

      def index
        @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: VERDICT_TABS)
        @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
        inspections = @sorting.apply(@filtering.apply(UrlInspection.all)).includes(:crawled_page)

        respond_to do |format|
          format.html do
            @pagination = Pagination.new(inspections, params)
            @url_inspections = @pagination.records
            @tab_counts = @filtering.tab_counts(UrlInspection.all)
            @uninspected_count = CrawledPage.not_in(_id: UrlInspection.distinct(:crawled_page_id)).count
            @new_entries = NewEntries.new.not_indexed
            # Searched but not narrowed to a verdict, so the chart shows how
            # the excluded pages compare with the indexed ones.
            @coverage_counts = UrlInspection.coverage_counts(@filtering.searched(UrlInspection.all))
            @crawl_delays = CrawlDelays.new
            @dropped = UrlInspectionHistory.dropped
          end
          format.csv do
            send_csv UrlInspection.to_csv(inspections), filename: "url-inspections-#{Date.current.iso8601}.csv"
          end
        end
      end

      def show
        @url_inspection = UrlInspection.find(params[:id])
        @timeline = @url_inspection.crawled_page ? UrlInspectionHistory.timeline(@url_inspection.crawled_page).to_a : []
      end

      # A batch rather than a range of days, since Google allows only so many
      # inspections a day.
      def sync
        SyncRequest.enqueue("url_inspections", limit: UrlInspectionSyncService::DEFAULT_LIMIT)
        redirect_to google_search_console_url_inspections_path,
          notice: "Inspecting the next #{UrlInspectionSyncService::DEFAULT_LIMIT} pages in the background, never-inspected ones first. " \
            "Refresh in a moment to see the new verdicts."
      end
    end
  end
end
