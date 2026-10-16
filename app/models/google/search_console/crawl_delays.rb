# encoding: UTF-8

module Google
  module SearchConsole
    # How long Google takes to first crawl, or to index, a new entry, so a
    # slowdown shows before it costs a post its first weeks of search traffic.
    class CrawlDelays
      # Labelled in days alone, since the axis is titled and a narrow card
      # has room for little more.
      BUCKETS = {"0" => 0..0, "1" => 1..1, "2–3" => 2..3, "4–7" => 4..7, "8–14" => 8..14, "15–28" => 15..28, "29+" => 29..}.freeze

      def initialize(field = :first_crawled_at)
        @field = field
      end

      # Only entries first inspected while still new: an older page's first
      # inspection may come long after its first crawl, which Google no
      # longer reports.
      def days
        @days ||= begin
          published = FeedEntry.where(:published_at.ne => nil).only(:_id, :published_at).to_h { |entry| [entry.url, entry.published_at] }
          pages = CrawledPage.where(:url.in => published.keys).only(:_id, :url).index_by(&:id)
          UrlInspection.where(:crawled_page_id.in => pages.keys, @field.ne => nil)
            .only(:crawled_page_id, @field, :created_at).filter_map do |inspection|
              published_at = published[pages[inspection.crawled_page_id].url]
              next if inspection.created_at > published_at + NewEntries::DAYS.days

              delay = (inspection[@field].to_date - published_at.to_date).to_i
              # A crawl before publishing was of the URL's earlier life.
              delay unless delay.negative?
            end
        end
      end

      def counts
        BUCKETS.transform_values { |range| days.count { |delay| range.cover?(delay) } }
      end

      def median
        return if days.empty?

        sorted = days.sort
        (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
      end
    end
  end
end
