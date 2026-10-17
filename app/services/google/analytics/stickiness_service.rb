# encoding: UTF-8

module Google
  module Analytics
    # Asked of GA live rather than synced, since each day's figure counts
    # readers over the days before it and none of them can be added up.
    # Cached, since a day's rolling figures only change as GA settles them.
    class StickinessService
      CACHE_FOR = 1.hour
      # GA's rolling actives, as its own User activity over time card shows
      # them, and how many of the longer span's readers each shorter one holds.
      METRICS = {
        daily: "active1DayUsers", weekly: "active7DayUsers", monthly: "active28DayUsers",
        dau_per_mau: "dauPerMau", dau_per_wau: "dauPerWau", wau_per_mau: "wauPerMau"
      }.freeze
      RATIOS = %i[dau_per_mau dau_per_wau wau_per_mau].freeze

      Day = Struct.new(:date, *METRICS.keys, keyword_init: true)
      Result = Struct.new(:days, :errors, keyword_init: true) do
        def any?
          days.any? { |day| day.monthly.to_i.positive? }
        end

        # Over the days GA had a figure for, so a gap isn't read as nobody.
        def average(metric)
          values = days.filter_map(&metric)
          values.sum.fdiv(values.size) if values.any?
        end

        def latest(metric)
          days.reverse_each.lazy.filter_map(&metric).first
        end
      end

      class << self
        def call(...)
          new.call(...)
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
        @hostname = options.fetch(:hostname) { Blog.host }
      end

      def call(period)
        stored = stored_days(period)
        return Result.new(days: stored, errors: []) if stored
        return Result.new(days: [], errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        return Result.new(days: [], errors: ["No Analytics property configured (credentials google.analytics_property_id)"]) if @property.blank?

        key = "google/analytics_stickiness/#{@property}/#{period.from}/#{period.to}"
        Result.new(days: @cache.fetch(key, expires_in: CACHE_FOR) { fetch(period) }, errors: [])
      rescue ApiClient::Error => e
        Result.new(days: [], errors: ["Analytics stickiness: #{e.message}"])
      end

      private

      # Only when every day of the period is stored, so a day the sync
      # hasn't reached isn't drawn as a gap GA wouldn't have.
      def stored_days(period)
        stats = SiteDayStat.where(date: period.from..period.to).index_by(&:date)
        return unless (period.from..period.to).all? { |date| stats.key?(date) }

        (period.from..period.to).map do |date|
          stat = stats[date]
          daily, weekly, monthly = stat.active_1_day_users, stat.active_7_day_users, stat.active_28_day_users
          Day.new(date: date, daily: daily, weekly: weekly, monthly: monthly,
            dau_per_mau: ratio(daily, monthly), dau_per_wau: ratio(daily, weekly), wau_per_mau: ratio(weekly, monthly))
        end
      end

      def ratio(part, whole)
        whole.positive? ? part.fdiv(whole) : 0.0
      end

      # Every day of the period, nil where GA had no row, so a chart's days
      # line up with the period's.
      def fetch(period)
        report = @client.post(format(SyncService::REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          dimensions: [{name: "date"}],
          metrics: METRICS.values.map { |name| {name: name} },
          dimensionFilter: SyncService.dimension_filter([], @hostname),
          returnPropertyQuota: true
        })
        Quota.record("core", report)

        metrics = Array(report["metricHeaders"]).map { |header| METRICS.key(header["name"]) }
        rows = Array(report["rows"]).to_h do |row|
          values = metrics.zip(Array(row["metricValues"]).map { |value| value["value"] }).select(&:first).to_h do |metric, value|
            [metric, RATIOS.include?(metric) ? value.to_f : value.to_i]
          end
          [Date.strptime(row.dig("dimensionValues", 0, "value"), "%Y%m%d"), values]
        end
        (period.from..period.to).map { |date| Day.new(date: date, **rows.fetch(date, {})) }
      end
    end
  end
end
