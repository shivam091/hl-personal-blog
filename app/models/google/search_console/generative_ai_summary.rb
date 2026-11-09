# encoding: UTF-8

module Google
  module SearchConsole
    # Generative AI figures for the pages beyond its own that show them.
    # Uploads are kept per search type, and Google doesn't say whether one
    # type's impressions are also another's, so adding them up could count
    # one twice. The type with the most days stands for them instead, as it
    # does when the Generative AI page opens, so the figures match it.
    class GenerativeAiSummary
      # Google shows the report's last few days within a day or two, so an
      # upload reaching no closer than this is one worth making again.
      STALE_DAYS = 10
      METRIC = DailyReport::Metric.new(field: :ai_impressions, label: "AI impressions", format: :count, icon: "sparkles",
        hint: "How often the blog appeared in an AI Overview or AI Mode answer, from the latest uploads of Search Console's Generative AI report.")

      attr_reader :period, :search_type

      def initialize(period, search_type: GenerativeAiStat.search_types.first)
        @period = period
        @search_type = search_type
      end

      def any?
        search_type.present?
      end

      # None, rather than zero, while no uploaded day falls in the period,
      # so a gap in the uploads doesn't read as the blog being shown nowhere.
      def total(within = period)
        days = by_date(within)
        days.values.sum if days.any?
      end

      # Only with days uploaded from before the period compared with, since
      # one before the first upload would read as a jump from nothing. Never
      # against another country, since Google doesn't split days by one.
      def previous_total
        total(period.previous) if previous_uploaded?
      end

      def previous_uploaded?
        any? && !period.compare_countries? && stats.where(:date.lte => period.previous.from).exists?
      end

      # A value for each day of the period, none for a day not uploaded.
      def daily(within = period)
        days = by_date(within)
        (within.from..within.to).map { |day| days[day] }
      end

      def by_date(within = period)
        return {} unless any?

        (@by_date ||= {})[[within.from, within.to]] ||= within.apply(stats).pluck(:date, :impressions).to_h
      end

      def first_day
        stats.min(:date) if any?
      end

      def last_day
        stats.max(:date) if any?
      end

      # From the breakdowns rather than the days, since every upload inserts
      # them anew while a day it leaves unchanged keeps its old timestamp.
      def uploaded_at
        (rows.order(_id: :desc).first&.id&.generation_time || stats.max(:updated_at))&.in_time_zone if any?
      end

      def stale?(today: Date.current)
        any? && last_day < today - STALE_DAYS
      end

      # The pages, countries and devices are Google's totals over the latest
      # upload's whole range, with no days, so they can't follow a period;
      # the range is shown with them instead.
      def covered
        return @covered if defined?(@covered)

        @covered = rows.first&.then { |row| row.from..row.to }
      end

      # By path, as every other page figure is kept, so the two line up.
      def pages
        @pages ||= rows.where(breakdown: "pages").pluck(:label, :impressions).each_with_object(Hash.new(0)) do |(url, impressions), paths|
          path = page_path(url)
          paths[path] += impressions if path
        end
      end

      # By alpha-2 code, leaving out a country Google names some new way.
      def countries
        @countries ||= rows.where(breakdown: "countries", :country.ne => nil).pluck(:country, :impressions)
          .each_with_object(Hash.new(0)) { |(code, impressions), codes| codes[code] += impressions }
      end

      private

      def stats
        GenerativeAiStat.where(search_type: search_type)
      end

      def rows
        any? ? GenerativeAiRow.where(search_type: search_type) : GenerativeAiRow.none
      end

      def page_path(url)
        URI.parse(url).path.presence || "/"
      rescue URI::InvalidURIError
        nil
      end
    end
  end
end
