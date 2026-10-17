# encoding: UTF-8

require "csv"

module Google
  module Analytics
    # Asked of GA live rather than synced, since a cohort follows the same
    # readers week after week and can't be added up from daily rows. Cached,
    # since the grid only changes once a week.
    class CohortService
      CACHE_FOR = 6.hours
      # A quarter of weekly cohorts, enough to see whether readers who came
      # after a change stay longer than those before it.
      WEEKS = 12
      # Short spans for a recent change, half a year for a slow trend.
      WEEK_CHOICES = [4, 8, 12, 16, 26].freeze
      # As GA names devices, so a choice matches its rows.
      DEVICES = ["desktop", "mobile", "tablet", "smart tv"].freeze

      Cohort = Struct.new(:start, :users, :active, keyword_init: true) do
        # Nil for a week the cohort hasn't reached yet, so it reads as blank
        # rather than as everyone having left.
        def retention(week)
          active[week].fdiv(users) if active[week] && users.positive?
        end
      end
      Result = Struct.new(:cohorts, :weeks, :errors, keyword_init: true)

      class << self
        def call(...)
          new.call(...)
        end

        # Counts beside shares, so a share from a handful of readers can be
        # told from one from hundreds.
        def to_csv(result)
          later = (1...result.weeks).to_a
          CSV.generate do |csv|
            csv << ["First visit week", "Readers", *later.flat_map { |week| ["Week #{week} back", "Week #{week} share"] }]
            result.cohorts.each do |cohort|
              csv << [cohort.start.iso8601, cohort.users, *later.flat_map { |week| [cohort.active[week], cohort.retention(week)&.round(4)] }]
            end
          end
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
        @hostname = options.fetch(:hostname, SyncService::HOSTNAME)
      end

      # Whole weeks from Sunday, as GA's own weeks run, ending with the last
      # complete one. A span or device not offered is read as the default,
      # so a mistyped link still shows a grid.
      def call(today: Date.current, weeks: WEEKS, country: nil, device: nil)
        weeks = weeks.to_i.presence_in(WEEK_CHOICES) || WEEKS
        country = country.to_s.upcase.presence
        device = device.presence_in(DEVICES)
        filters = [(["countryId", "EXACT", country] if country), (["deviceCategory", "EXACT", device] if device)].compact
        return Result.new(cohorts: [], weeks: weeks, errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        if @property.blank?
          return Result.new(
            cohorts: [],
            weeks: weeks,
            errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
          )
        end

        last = today.beginning_of_week(:sunday) - 7
        starts = (0...weeks).map { |back| last - back * 7 }.reverse
        key = "google/analytics_cohorts/#{@property}/#{last}/#{weeks}/#{country}/#{device}"
        cohorts = @cache.fetch(key, expires_in: CACHE_FOR) { fetch(starts, today, weeks, filters) }
        Result.new(cohorts: cohorts, weeks: weeks, errors: [])
      rescue ApiClient::Error => e
        Result.new(cohorts: [], weeks: weeks, errors: ["Analytics cohorts: #{e.message}"])
      end

      private

      def fetch(starts, today, weeks, filters)
        report = @client.post(format(SyncService::REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dimensions: [{name: "cohort"}, {name: "cohortNthWeek"}],
          metrics: [{name: "cohortActiveUsers"}, {name: "cohortTotalUsers"}],
          cohortSpec: {
            cohorts: starts.map do |start|
              {
                name: start.iso8601,
                dimension: "firstSessionDate",
                dateRange: {startDate: start.iso8601, endDate: (start + 6).iso8601}
              }
            end,
            cohortsRange: {granularity: "WEEKLY", startOffset: 0, endOffset: weeks - 1}
          },
          dimensionFilter: SyncService.dimension_filter(filters, @hostname),
          returnPropertyQuota: true
        })
        Quota.record("core", report)

        rows = Array(report["rows"]).map { |row|
        [*row["dimensionValues"].map { |value| value["value"] }, *row["metricValues"].map { |value| value["value"].to_i }] }
        starts.map do |start|
          mine = rows.select { |name, *| name == start.iso8601 }
          # Only finished weeks: one still under way, or yet to come, would
          # read as readers not coming back.
          reached = ((today - start).to_i / 7).clamp(0, weeks)
          active = mine.to_h { |_, week, users, _| [week.to_i, users] }
          Cohort.new(
            start: start,
            users: mine.map(&:last).max.to_i,
            active: (0...reached).to_h { |week| [week, active.fetch(week, 0)] }
          )
        end
      end
    end
  end
end
