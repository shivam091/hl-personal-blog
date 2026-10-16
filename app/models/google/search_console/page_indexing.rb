# encoding: UTF-8

module Google
  module SearchConsole
    # Rebuilt from our own inspections because Search Console's API offers no
    # Page indexing history, so a drop can be dated rather than only seen.
    class PageIndexing
      PAGES = {"all" => "All known pages", "submitted" => "All submitted pages", "unsubmitted" => "Unsubmitted pages only"}.freeze
      RANGES = {"28" => "Last 28 days", "90" => "Last 3 months", "180" => "Last 6 months", "365" => "Last 12 months"}.freeze
      DEFAULT_RANGE = "90"
      SERIES = %w[not_indexed indexed impressions].freeze
      DEFAULT_SHOWN = %w[not_indexed indexed].freeze

      Reason = Struct.new(:coverage_state, :count, keyword_init: true)

      attr_reader :pages, :range, :shown

      def initialize(params = {}, today: Date.current)
        @today = today
        @pages = params[:indexing_pages].presence_in([*PAGES.keys, *sitemaps]) || "all"
        @range = params[:indexing_range].presence_in(RANGES.keys) || DEFAULT_RANGE
        picked = SERIES & params[:indexing_show].to_s.split(",")
        @shown = picked.presence || DEFAULT_SHOWN
      end

      # Every sitemap Google says a page was found in, with the ones Search
      # Console lists, so a sitemap no inspected page is in yet still shows.
      def sitemaps
        @sitemaps ||= (UrlInspection.distinct(:sitemaps) | Sitemap.distinct(:path)).compact_blank.sort
      end

      def sitemap?
        sitemaps.include?(pages)
      end

      def dates
        @dates ||= ((@today - range.to_i + 1)..@today).to_a
      end

      def shown?(series)
        shown.include?(series)
      end

      # The last shown series can't be switched off so the chart is never empty.
      def toggle(series)
        return series if shown == [series]

        picked = SERIES & (shown?(series) ? shown - [series] : shown + [series])
        picked == DEFAULT_SHOWN ? "" : picked.join(",")
      end

      # A synced day with none shown is a real zero while an unsynced one is
      # nil, so it isn't drawn as a day of none.
      def impressions
        @impressions ||= begin
          criteria = Stat.page_totals.where(search_type: "web", :page_path.in => paths, date: dates.first..dates.last)
          rows = Stat.grouped(criteria, by: [:date]).index_by(&:date)
          synced = Stat.site_totals.where(search_type: "web", date: dates.first..dates.last).distinct(:date).map(&:to_date).to_set
          dates.map { |date| rows[date]&.impressions || (0 if synced.include?(date)) }
        end
      end

      def indexed
        inspections.count(&:indexed?)
      end

      def not_indexed
        inspections.size - indexed
      end

      def any?
        inspections.any?
      end

      def reasons
        inspections.reject(&:indexed?).map { |inspection| inspection.coverage_state.presence || "Unknown" }.tally
          .map { |state, count| Reason.new(coverage_state: state, count: count) }.sort_by { |row| [-row.count, row.coverage_state] }
      end

      # Nil before any picked page was inspected so it isn't drawn as a day of
      # none.
      def daily
        @daily ||= begin
          counts = dates.map do |date|
            at = date.end_of_day
            # Not filter_map, which would drop the unindexed pages' false.
            states = timelines.map { |rows| rows.reverse_each.find { |time, _| time <= at }&.last }.reject(&:nil?)
            states.empty? ? [nil, nil] : [states.count(false), states.count(true)]
          end
          {"not_indexed" => counts.map(&:first), "indexed" => counts.map(&:last)}
        end
      end

      private

      def paths
        CrawledPage.where(:id.in => inspections.map(&:crawled_page_id)).pluck(:url).filter_map { |url| IndexCoverage.path_of(url) }
      end

      # Pages still crawled only, since a removed page's last verdict would
      # otherwise be counted forever. Sitemaps are as of the latest
      # inspection, as Google keeps no record of them over time either.
      def inspections
        @inspections ||= begin
          scope = UrlInspection.only(:crawled_page_id, :verdict, :coverage_state, :inspected_at, :sitemaps)
          scope = case pages
          when "all" then scope
          when "submitted" then scope.where("sitemaps.0" => {"$exists" => true})
          when "unsubmitted" then scope.where("sitemaps.0" => {"$exists" => false})
          else scope.where(sitemaps: pages)
          end
          scope.to_a
        end
      end

      # Only changes are kept, so a page's rows are when its verdict moved;
      # one inspected before that was kept stands on its latest inspection.
      def timelines
        @timelines ||= begin
          histories = UrlInspectionHistory.where(:crawled_page_id.in => inspections.map(&:crawled_page_id))
            .only(:crawled_page_id, :inspected_at, :verdict).order(inspected_at: :asc).group_by(&:crawled_page_id)
          inspections.map do |inspection|
            (histories[inspection.crawled_page_id].presence || [inspection]).filter_map do |row|
              [row.inspected_at, row.verdict == "PASS"] if row.inspected_at
            end
          end
        end
      end
    end
  end
end
