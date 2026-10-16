# encoding: UTF-8

require "csv"

module Google
  module SearchConsole
    # Copied so why a page isn't indexed (blocked, a soft 404, a different
    # canonical) can be read off rather than looked up page by page.
    class UrlInspection
      include Mongoid::Document
      include Mongoid::Timestamps

      belongs_to :crawled_page

      field :inspected_at, type: Time
      field :verdict, type: String
      # Search Console's own wording, so it can be searched for in its help.
      field :coverage_state, type: String
      field :robots_txt_state, type: String
      field :indexing_state, type: String
      field :page_fetch_state, type: String
      field :crawled_as, type: String
      field :last_crawled_at, type: Time
      # Kept apart from the last crawl, which Google moves on every recrawl,
      # so how long a new entry waited for its first is still known later.
      field :first_crawled_at, type: Time
      # Kept apart from the verdict, which each inspection overwrites, so when
      # a page got in is still known after it drops out and comes back.
      field :first_indexed_at, type: Time
      # Google doesn't say when it indexed a page, only what a check found,
      # so this is the latest the page is known not to have been.
      field :indexed_after, type: Time
      field :google_canonical, type: String
      field :user_canonical, type: String
      field :sitemaps, type: Array, default: []
      field :referring_urls, type: Array, default: []
      field :rich_results_verdict, type: String
      field :rich_results, type: Array, default: []
      field :inspection_link, type: String

      index({crawled_page_id: 1}, {unique: true})
      # Sorts carry an _id tiebreaker, which an index without it can't serve;
      # read backwards it also serves the oldest-first inspection queue.
      index({inspected_at: -1, _id: 1})
      index({verdict: 1})

      def indexed?
        verdict == "PASS"
      end

      # Google indexing another URL in this page's place is a common, quiet
      # reason a page gets no search traffic.
      def canonical_mismatch?
        google_canonical.present? && user_canonical.present? && google_canonical != user_canonical
      end

      def to_s
        crawled_page&.url || "Removed page"
      end

      CoverageCount = Struct.new(:coverage_state, :verdict, :count, keyword_init: true)

      class << self
        # Grouped with the verdict too, so each state is coloured by what
        # Google made of it; most pages first, since that's where to look.
        def coverage_counts(scope)
          scope.collection.aggregate([
            {"$match" => scope.selector},
            {"$group" => {"_id" => {"coverage" => "$coverage_state", "verdict" => "$verdict"}, "count" => {"$sum" => 1}}}
          ]).map do |row|
            CoverageCount.new(coverage_state: row["_id"]["coverage"].presence || "Unknown", verdict: row["_id"]["verdict"], count: row["count"])
          end.sort_by { |row| [-row.count, row.coverage_state] }
        end

        def to_csv(inspections)
          CSV.generate do |csv|
            csv << ["URL", "Verdict", "Coverage", "Indexing", "Robots.txt", "Page fetch", "Crawled as", "Last crawled",
              "Indexed after", "First indexed", "Google canonical", "Declared canonical", "Rich results", "Inspected", "Search Console link"]
            inspections.each do |inspection|
              csv << [inspection.to_s, inspection.verdict, inspection.coverage_state, inspection.indexing_state,
                inspection.robots_txt_state, inspection.page_fetch_state, inspection.crawled_as, inspection.last_crawled_at&.utc&.iso8601,
                inspection.indexed_after&.utc&.iso8601, inspection.first_indexed_at&.utc&.iso8601,
                inspection.google_canonical, inspection.user_canonical, inspection.rich_results_verdict,
                inspection.inspected_at&.utc&.iso8601, inspection.inspection_link]
            end
          end
        end
      end
    end
  end
end
