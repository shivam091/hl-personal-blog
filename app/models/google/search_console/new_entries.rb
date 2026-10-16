# encoding: UTF-8

module Google
  module SearchConsole
    # Followed until Google indexes them because a new entry is when indexing
    # matters most, and the one a daily batch over the whole blog is slowest
    # to get round to.
    class NewEntries
      # Long enough for Google to get round to most new pages.
      DAYS = 30
      # Google rarely changes its mind within a day or two, so a still-unindexed
      # entry is looked at again this often rather than every run.
      RECHECK_AFTER = 3.days

      Row = Struct.new(:entry, :page, :inspection, keyword_init: true) do
        def indexed?
          page&.indexed || false
        end

        def status
          if page.nil? then "Not in the sitemap, so not inspected"
          elsif inspection.nil? then "Not inspected yet"
          else inspection.coverage_state.presence || inspection.verdict.to_s.humanize
          end
        end
      end

      def initialize(now: Time.current)
        @now = now
      end

      # Newest first, since the newest has had least time to be picked up.
      def rows
        @rows ||= begin
          entries = FeedEntry.where(:published_at.gte => @now - DAYS.days).order(published_at: :desc).to_a
          pages = CrawledPage.where(:url.in => entries.map(&:url)).includes(:url_inspection).index_by(&:url)
          entries.map do |entry|
            Row.new(entry: entry, page: pages[entry.url], inspection: pages[entry.url]&.url_inspection)
          end
        end
      end

      def not_indexed
        rows.reject(&:indexed?)
      end

      def pages_due
        not_indexed.select do |row|
          row.page &&
            (
              row.inspection.nil? ||
              row.inspection.inspected_at.nil? ||
              row.inspection.inspected_at <= @now - RECHECK_AFTER
            )
        end.map(&:page)
      end
    end
  end
end
