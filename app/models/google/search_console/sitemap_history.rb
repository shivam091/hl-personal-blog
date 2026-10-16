# encoding: UTF-8

module Google
  module SearchConsole
    # A Sitemap is overwritten by each sync, so a sitemap whose URLs or
    # errors changed would show only its new state. A row per sync rather
    # than per change, since there are only a few sitemaps and a steady line
    # says the sitemap was still being read.
    class SitemapHistory
      include Mongoid::Document
      include Mongoid::Timestamps

      field :path, type: String
      field :synced_at, type: Time
      field :submitted, type: Integer, default: 0
      # Search Console stopped filling its own indexed count, so this is the
      # pages inspected as indexed that Google found in this sitemap; nil
      # before any page was inspected.
      field :indexed, type: Integer
      field :error_count, type: Integer, default: 0
      field :warning_count, type: Integer, default: 0
      field :pending, type: Boolean, default: false
      field :last_downloaded_at, type: Time

      index({path: 1, synced_at: -1})
      index({synced_at: -1})

      validates :path, :synced_at, presence: true

      class << self
        def record(sitemap, synced_at: Time.current)
          inspected = UrlInspection.where(sitemaps: sitemap.path)
          create(path: sitemap.path, synced_at: synced_at, submitted: sitemap.submitted_urls,
            indexed: (inspected.where(verdict: "PASS").count if inspected.exists?), error_count: sitemap.error_count,
            warning_count: sitemap.warning_count, pending: sitemap.pending, last_downloaded_at: sitemap.last_downloaded_at)
        end

        # A day's last sync per sitemap, added up across sitemaps, so each
        # day is one point however often it was synced.
        def daily(scope = all, days: 90)
          rows = scope.where(:synced_at.gte => days.days.ago).order(synced_at: :asc).to_a
          by_day = rows.group_by { |row| row.synced_at.to_date }.transform_values { |day| day.index_by(&:path).values }
          by_day.transform_values do |day|
            {submitted: day.sum(&:submitted), indexed: (day.filter_map(&:indexed).sum if day.any?(&:indexed)),
             errors: day.sum(&:error_count), warnings: day.sum(&:warning_count)}
          end
        end

        # Only syncs where a count moved, so a sitemap's few changes aren't
        # lost among its identical rows.
        def changes(path, limit: 10)
          rows = where(path: path).order(synced_at: :asc).to_a
          figures = ->(row) { [row.submitted, row.indexed, row.error_count, row.warning_count] }
          rows.select.with_index { |row, index| index.zero? || figures.(row) != figures.(rows[index - 1]) }.last(limit).reverse
        end
      end
    end
  end
end
