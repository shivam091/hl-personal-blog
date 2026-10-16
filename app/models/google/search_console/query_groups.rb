# encoding: UTF-8

module Google
  module SearchConsole
    class QueryGroups
      # Searches naming the blog or its author, which find it however well
      # it ranks; the rest is what ranking actually earns.
      BRAND = /harshal|ladhe/i
      BRANDED = "Branded"
      NON_BRANDED = "Non-branded"

      # Checked in order, first match wins, so "how to fix X error" is a
      # problem to solve before it's a question. What matches none is a bare
      # topic, someone searching a term to read about it.
      INTENTS = {
        "Troubleshooting" => /\b(error|errors|not working|doesn'?t work|fix|fixed|issue|bug|fail(s|ed|ing)?|undefined|cannot|can'?t|unable)\b/i,
        "Comparison" => /\b(vs\.?|versus|difference|differences|compare|comparison|or|alternatives?)\b/i,
        "Question" => /\A(how|what|why|when|where|which|who|can|does|do|is|are|should)\b|\?\z/i,
        "Learning" => /\b(tutorial|guide|example|examples|basics|cheat ?sheet|explained|learn|introduction|beginners?)\b/i
      }.freeze
      TOPIC = "Topic"

      Group = Struct.new(:name, :queries, :clicks, :impressions, :weighted_position, :top, keyword_init: true) do
        def ctr
          clicks.fdiv(impressions) if impressions.positive?
        end

        # Weighted by impressions, as Search Console averages it.
        def position
          weighted_position.fdiv(impressions) if impressions.positive?
        end
      end

      attr_reader :period, :country

      def initialize(period, country: nil)
        @period = period
        @country = country
      end

      def brand_split
        groups([BRANDED, NON_BRANDED]) { |query| brand(query) }
      end

      def intent_split
        groups([*INTENTS.keys, TOPIC]) { |query| intent(query) }
      end

      # Nil on a day not synced, so a gap in the import isn't drawn as a day
      # without clicks.
      def daily_brand_clicks
        rows = Stat.grouped(period.apply(query_criteria), by: [:date, :query]).to_a
        synced = Stat.grouped(period.apply(Stat.site_totals), by: [:date]).to_set(&:date)
        dates = (period.from..period.to).to_a
        [BRANDED, NON_BRANDED].index_with do |name|
          clicks = rows.select { |row| brand(row[:query]) == name }.group_by(&:date).transform_values { |day| day.sum(&:clicks) }
          dates.map { |date| clicks.fetch(date, 0) if synced.include?(date) }
        end
      end

      private

      def brand(query)
        query.to_s.match?(BRAND) ? BRANDED : NON_BRANDED
      end

      def intent(query)
        INTENTS.find { |_, pattern| query.to_s.match?(pattern) }&.first || TOPIC
      end

      def rows
        @rows ||= Stat.grouped(period.apply(query_criteria), by: [:query]).to_a
      end

      # So a country's searches are grouped on their own rather than mixed in
      # with every other's.
      def query_criteria
        country ? QueryCountryStat.site_wide.where(country: country) : Stat.by_query.site_wide
      end

      # Every group named, in order, even one with no queries, so a missing
      # kind of search reads as none rather than not being asked about. The
      # most seen queries are kept as examples of what fell in each.
      def groups(names, examples: 3)
        by_name = rows.group_by { |row| yield(row[:query]) }
        names.map do |name|
          matched = by_name.fetch(name, [])
          Group.new(name: name, queries: matched.size, clicks: matched.sum(&:clicks), impressions: matched.sum(&:impressions),
            weighted_position: matched.sum { |row| row[:weighted_position].to_f },
            top: matched.sort_by { |row| [-row.impressions, row[:query].to_s] }.first(examples).map { |row| row[:query] })
        end
      end
    end
  end
end
