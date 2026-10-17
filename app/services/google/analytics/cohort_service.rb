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
        starts = starts(today, weeks)
        # Only the whole site's cohorts are stored; a country's or device's
        # would be one more copy per choice.
        stored = stored_cohorts(starts, today, weeks) if filters.empty?
        return Result.new(cohorts: stored, weeks: weeks, errors: []) if stored
        return Result.new(cohorts: [], weeks: weeks, errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        if @property.blank?
          return Result.new(
            cohorts: [],
            weeks: weeks,
            errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
          )
        end

        key = "google/analytics_cohorts/#{@property}/#{starts.last}/#{weeks}/#{country}/#{device}"
        cohorts = @cache.fetch(key, expires_in: CACHE_FOR) { build(starts, today, weeks, fetch(starts, weeks, filters)) }
        Result.new(cohorts: cohorts, weeks: weeks, errors: [])
      rescue ApiClient::Error => e
        Result.new(cohorts: [], weeks: weeks, errors: ["Analytics cohorts: #{e.message}"])
      end

      # Only weeks GA returned, so a cohort with no readers isn't stored as
      # one that had them and lost them all; and only finished ones, since a
      # week under way would be stored short.
      def finished_weeks(today: Date.current)
        weeks = WEEK_CHOICES.max
        fetch(starts(today, weeks), weeks, []).filter_map do |start, week, active, total|
          start = Date.iso8601(start)
          {date: start, week: week.to_i, active_users: active, total_users: total} if week.to_i < reached(start, today, weeks)
        end
      end

      private

      def starts(today, weeks)
        last = today.beginning_of_week(:sunday) - 7
        (0...weeks).map { |back| last - back * 7 }.reverse
      end

      def reached(start, today, weeks)
        ((today - start).to_i / 7).clamp(0, weeks)
      end

      # Only once the latest finished week is stored, so the grid is never a
      # week behind.
      def stored_cohorts(starts, today, weeks)
        return unless CohortWeekStat.where(date: starts.last, week: 0).exists?

        rows = CohortWeekStat.where(:date.in => starts).map { |stat| [stat.date.iso8601, stat.week.to_s, stat.active_users, stat.total_users] }
        build(starts, today, weeks, rows)
      end

      def fetch(starts, weeks, filters)
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

        Array(report["rows"]).map do |row|
          [*row["dimensionValues"].map { |value| value["value"] }, *row["metricValues"].map { |value| value["value"].to_i }]
        end
      end

      def build(starts, today, weeks, rows)
        starts.map do |start|
          mine = rows.select { |name, *| name == start.iso8601 }
          # Only finished weeks: one still under way, or yet to come, would
          # read as readers not coming back.
          active = mine.to_h { |_, week, users, _| [week.to_i, users] }
          Cohort.new(
            start: start,
            users: mine.map(&:last).max.to_i,
            active: (0...reached(start, today, weeks)).to_h { |week| [week, active.fetch(week, 0)] }
          )
        end
      end
    end
  end
end
