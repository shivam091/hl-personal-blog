# encoding: UTF-8

module Google
  module Analytics
    # GA counts a session once for every page it touched, so per-page rows
    # can't be added up into sessions: site-wide sessions come from landing
    # pages, where each session has exactly one, and anything split by page
    # or source is counted in views, which do add up.
    class Summary
      attr_reader :period, :country

      def initialize(period, country: nil)
        @period = period
        @country = country
      end

      def any?
        Stat.exists?
      end

      def views(within = period)
        Stat.grouped(views_criteria(within), by: []).totals.views
      end

      # Landing pages have no country breakdown, so sessions are always the
      # whole site's.
      def sessions(within = period)
        @sessions ||= {}
        @sessions[within.key] ||= LandingSourceStat.grouped(within.apply(LandingSourceStat.all), by: []).totals
      end

      def engagement_seconds_per_session(within = period)
        sessions = sessions(within).sessions
        return unless sessions.positive?

        @engagement_seconds ||= {}
        @engagement_seconds[within.key] ||= Stat.grouped(within.apply(Stat.all), by: []).totals.engagement_seconds
        @engagement_seconds[within.key] / sessions
      end

      def previous?
        return @previous if defined?(@previous)

        @previous = period.compare_countries? || Stat.where(:date.lte => period.previous.from).exists?
      end

      # Nil on days not synced, so a gap in the import isn't drawn as no views.
      def daily_views(within = period)
        @daily_views ||= {}
        @daily_views[within.key] ||= begin
          rows = Stat.grouped(views_criteria(within), by: [:date]).to_h { |row| [row[:date].to_date, row.views] }
          synced = days_with_data(within).to_set
          (within.from..within.to).map { |date| rows.fetch(date, 0) if synced.include?(date) }
        end
      end

      def pages(within = period)
        Stat.grouped(views_criteria(within), by: [:page_path]).index_by { |row| row[:page_path] }
      end

      def page_totals(page_path, within = period)
        Stat.grouped(within.apply(Stat.where(page_path: page_path)), by: []).totals
      end

      def countries(within = period)
        AudienceStat.grouped(within.apply(AudienceStat.all), by: [:country]).to_h { |row| [row[:country], row.views] }
      end

      def days_with_data(within = period)
        Stat.where(date: within.from..within.to).distinct(:date).map(&:to_date)
      end

      private

      def views_criteria(within)
        code = within.country || country
        within.apply(code ? AudienceStat.where(country: code) : Stat.all)
      end
    end
  end
end
