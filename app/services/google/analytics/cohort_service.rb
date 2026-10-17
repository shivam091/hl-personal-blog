# encoding: UTF-8

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
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
        @hostname = options.fetch(:hostname, SyncService::HOSTNAME)
      end

      # Whole weeks from Sunday, as GA's own weeks run, ending with the last
      # complete one.
      def call(today: Date.current)
        return Result.new(cohorts: [], weeks: WEEKS, errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        if @property.blank?
          return Result.new(
            cohorts: [],
            weeks: WEEKS,
            errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
          )
        end

        last = today.beginning_of_week(:sunday) - 7
        starts = (0...WEEKS).map { |back| last - back * 7 }.reverse
        cohorts = @cache.fetch("google/analytics_cohorts/#{@property}/#{last}", expires_in: CACHE_FOR) do
          fetch(starts, today)
        end
        Result.new(cohorts: cohorts, weeks: WEEKS, errors: [])
      rescue ApiClient::Error => e
        Result.new(cohorts: [], weeks: WEEKS, errors: ["Analytics cohorts: #{e.message}"])
      end

      private

      def fetch(starts, today)
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
            cohortsRange: {granularity: "WEEKLY", startOffset: 0, endOffset: WEEKS - 1}
          },
          dimensionFilter: SyncService.dimension_filter([], @hostname),
          returnPropertyQuota: true
        })
        Quota.record("core", report)

        rows = Array(report["rows"]).map { |row|
        [*row["dimensionValues"].map { |value| value["value"] }, *row["metricValues"].map { |value| value["value"].to_i }] }
        starts.map do |start|
          mine = rows.select { |name, *| name == start.iso8601 }
          # Only finished weeks: one still under way, or yet to come, would
          # read as readers not coming back.
          reached = ((today - start).to_i / 7).clamp(0, WEEKS)
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
