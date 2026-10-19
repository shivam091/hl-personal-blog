# encoding: UTF-8

module Google
  module Analytics
    # Real readers' Web Vitals as the blog reports them to GA, since the
    # Chrome UX Report has too few Chrome users to say anything about the
    # blog yet, and covers no other browser. GA only sums an event's value,
    # so a mean is what can be read back, never the 75th percentile Google
    # judges a page by.
    class WebVitalStat
      include Mongoid::Document
      include DailyStat

      METRICS = %w[LCP INP CLS FCP TTFB].freeze
      RATINGS = %w[good needs-improvement poor].freeze
      # Google's good and poor bands for each metric, by the lowercase key
      # the pages use; applied to a mean as a guide only, since Google rates
      # the 75th percentile.
      THRESHOLDS = {
        "lcp" => [2500, 4000],
        "inp" => [200, 500],
        "cls" => [0.1, 0.25],
        "fcp" => [1800, 3000],
        "ttfb" => [800, 1800]
      }.freeze
      # The blog sends CLS a thousandfold, since GA keeps an event's value
      # to whole numbers.
      CLS_SCALE = 1000.0

      field :page_path, type: String
      field :metric, type: String
      field :rating, type: String
      field :event_count, type: Integer, default: 0
      field :value_sum, type: Float, default: 0.0

      key_fields :page_path, :metric, :rating

      index({date: 1, page_path: 1, metric: 1, rating: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      index({metric: 1, date: 1})
      index({page_path: 1, date: 1})

      validates :page_path, :metric, :rating, presence: true

      COUNTS = %i[event_count good_count needs_improvement_count poor_count].freeze
      GROUP_SUMS = {
        event_count: "$event_count",
        value_sum: "$value_sum",
        **RATINGS.to_h { |rating| [:"#{rating.underscore}_count", {"$cond" => [{"$eq" => ["$rating", rating]}, "$event_count", 0]}] }
      }.freeze
      # Over rated reports only, so events sent before the blog sent a rating
      # don't read as neither good nor poor.
      RATED = {"$add" => RATINGS.map { |rating| "$#{rating.underscore}_count" }}.freeze
      GROUP_DERIVED = {
        "mean_value" => {"$cond" => [{"$gt" => ["$event_count", 0]}, {"$divide" => ["$value_sum", "$event_count"]}, nil]},
        **RATINGS.to_h do |rating|
          ["#{rating.underscore}_share", {"$cond" => [{"$gt" => [RATED, 0]}, {"$divide" => ["$#{rating.underscore}_count", RATED]}, nil]}]
        end
      }.freeze

      class Total < GroupedScope::Row
        COUNTS.each do |count|
          define_method(count) { self[count].to_i }
        end

        def value_sum
          self[:value_sum].to_f
        end

        def rated_count
          good_count + needs_improvement_count + poor_count
        end

        # Nil rather than zero with nothing reported, so a page with no
        # readers' figures isn't read as instant.
        def mean_value
          value_sum.fdiv(event_count) if event_count.positive?
        end

        RATINGS.each do |rating|
          define_method(:"#{rating.underscore}_share") do
            public_send(:"#{rating.underscore}_count").fdiv(rated_count) if rated_count.positive?
          end
        end
      end

      class << self
        def rating(metric, value)
          return if value.nil?

          good, poor = THRESHOLDS.fetch(metric)
          if value <= good then :good
          elsif value <= poor then :needs_improvement
          else :poor
          end
        end

        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: GROUP_SUMS, derived: GROUP_DERIVED, row_class: Total)
        end

        # Scaled back here rather than when read, so every sum and mean is
        # already in CLS's own units.
        def sync(rows, result = SyncResult.empty, **)
          super(rows.map { |row| row[:metric]&.upcase == "CLS" ? row.merge(value_sum: row[:value_sum].to_f / CLS_SCALE) : row }, result, **)
        end

        # Per metric over the period, since one metric's figures can't be
        # added to another's.
        def overview(criteria)
          grouped(criteria, by: [:metric]).index_by { |row| row[:metric] }
        end

        # Pages whose readers wait longest, from enough reports that one slow
        # visit doesn't put a page on top.
        def slowest_pages(criteria, metric, min_reports:, limit: 5)
          grouped(criteria.where(metric: metric), by: [:page_path]).to_a
            .select { |row| row.event_count >= min_reports && row.mean_value }
            .sort_by { |row| [-row.mean_value, row[:page_path].to_s] }.first(limit)
        end
      end
    end
  end
end
