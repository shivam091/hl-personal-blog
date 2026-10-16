# encoding: UTF-8

module Google
  module SearchConsole
    # Read the way the blog's own figures are, so the two can sit side by
    # side. Every search type together, so a reader found through image or
    # video search counts as much as one found through web search.
    class Summary
      # Positions just off the first page, where a small push gains the most
      # clicks.
      OPPORTUNITY_POSITIONS = 4.5..15.5
      # Below this, a CTR or an average position is mostly noise.
      MIN_IMPRESSIONS = 50
      # Split at the halves, since an average position is fractional and 3.6
      # reads as 4th.
      POSITION_BUCKETS = {
        "1–3" => ...3.5,
        "4–10" => 3.5...10.5,
        "11–20" => 10.5...20.5,
        "21+" => 20.5..
      }.freeze
      # A page with less of a query's impressions than this is a stray
      # result, not one competing for it.
      COMPETING_SHARE = 0.1
      # Past the third page hardly anyone clicks, so CTR there says nothing.
      CURVE_POSITIONS = 30
      # How far under the site's usual CTR for its position a query has to
      # fall to be worth a better title, so ordinary scatter isn't flagged.
      CTR_SHORTFALL = 0.75
      EXPORTS = {
        "queries" => "Queries",
        "opportunities" => "Opportunities",
        "new" => "New queries",
        "lost" => "Lost queries",
        "pages" => "Low-CTR pages",
        "ctr" => "CTR by position",
        "competing" => "Pages competing for a query",
        "countries" => "Countries"
      }.freeze

      # Two or more of the blog's pages each shown for one query, splitting
      # Google's attention between them.
      Competition = Struct.new(:query, :clicks, :impressions, :pages, keyword_init: true)
      CtrPoint = Struct.new(:query, :position, :ctr, :clicks, :impressions, :expected, keyword_init: true) do
        def below?
          expected.to_f.positive? && ctr < expected * CTR_SHORTFALL
        end
      end

      attr_reader :period, :country

      def initialize(period, country: nil)
        @period = period
        @country = country
      end

      def any?
        Stat.exists?
      end

      # A country's figures come from the country breakdown, which Search
      # Console counts the same way as the site's totals.
      def totals(within = period)
        @totals ||= {}
        @totals[within.key] ||= Stat.grouped(totals_criteria(within), by: []).totals
      end

      # A period from before the first sync would read as a jump from zero.
      def previous_totals
        totals(period.previous) if previous_synced?
      end

      # Nil on days not synced, so a gap in the import isn't drawn as no clicks.
      def daily(field, within = period)
        @daily_rows ||= {}
        rows = @daily_rows[within.key] ||= Stat.grouped(totals_criteria(within), by: [:date]).index_by(&:date)
        (within.from..within.to).map { |date| rows[date]&.value(field) }
      end

      # So a country's queries can be judged against another's, as its totals are.
      def queries(within = period)
        @queries ||= {}
        @queries[within.key] ||= begin
          code = within.country || country
          criteria = code ? QueryCountryStat.site_wide.where(country: code) : Stat.by_query.site_wide
          Stat.grouped(within.apply(criteria), by: [:query]).to_a
        end
      end

      # So a ranking that's slipping shows before its clicks do.
      def previous_positions
        return {} unless compared?

        @previous_positions ||= queries(period.previous).to_h { |row| [row[:query], row.position] }
      end

      # So each top query's clicks and impressions can be read against the
      # same query then.
      def previous_queries
        return {} unless compared?

        @previous_queries ||= queries(period.previous).index_by { |row| row[:query] }
      end

      # Queries seen this period and not the one before, and the reverse, so
      # a post starting to rank for something, or dropping out, shows before
      # it moves the totals. Empty until the period before was synced, since
      # every query would otherwise read as new.
      def new_queries(limit: 10)
        return [] unless compared?

        before = queries(period.previous).to_set { |row| row[:query] }
        by_impressions(queries.reject { |row| before.include?(row[:query]) }, limit)
      end

      def lost_queries(limit: 10)
        return [] unless compared?

        now = queries.to_set { |row| row[:query] }
        by_impressions(queries(period.previous).reject { |row| now.include?(row[:query]) }, limit)
      end

      def previous_synced?
        return @previous_synced if defined?(@previous_synced)

        @previous_synced = period.compare_countries? || Stat.where(:date.lte => period.previous.from).exists?
      end

      # Whether a comparison was asked for and there's something to compare
      # with, so "No comparison" hides every change rather than the tiles'
      # alone.
      def compared?
        period.compare? && previous_synced?
      end

      def top_queries(limit: 10)
        queries.sort_by { |row| [-row.clicks, -row.impressions, row[:query].to_s] }.first(limit)
      end

      def opportunities(limit: 10)
        queries
          .select { |row| row.impressions >= MIN_IMPRESSIONS && row.position && OPPORTUNITY_POSITIONS.cover?(row.position) }
          .sort_by { |row| [-row.impressions, row[:query].to_s] }
          .first(limit || queries.size)
      end

      # Pages seen often but clicked less than the site usually is: their
      # titles and descriptions are the ones worth rewriting.
      def low_ctr_pages(limit: 10)
        site_ctr = totals.ctr
        pages
          .values
          .select { |row| row.impressions >= MIN_IMPRESSIONS && row.ctr < site_ctr }
          .sort_by { |row| [-row.impressions, row[:page_path].to_s] }
          .first(limit || pages.size)
      end

      # Queries more than one page takes a real share of, most seen first,
      # since that's where a merge or a clearer focus gains the most.
      def competing_queries(limit: 10)
        rows = Stat.grouped(period.apply(Stat.by_query.per_page), by: [:query, :page_path]).to_a
        competing = rows.group_by { |row| row[:query] }.filter_map do |query, pages|
          impressions = pages.sum(&:impressions)
          next if impressions < MIN_IMPRESSIONS

          shown = pages.select { |row| row.impressions >= impressions * COMPETING_SHARE }
          next if shown.size < 2

          Competition.new(
            query: query,
            clicks: pages.sum(&:clicks),
            impressions: impressions,
            pages: shown.sort_by { |row| [-row.impressions, row[:page_path].to_s] }
          )
        end
        competing.sort_by { |row| [-row.impressions, row.query.to_s] }.first(limit || competing.size)
      end

      # Each query seen often enough to judge, with the CTR the site's own
      # queries get around its position: the curve a title is measured
      # against is this blog's, not an industry average.
      def ctr_points
        @ctr_points ||= begin
          rows = queries.select { |row| row.impressions >= MIN_IMPRESSIONS && row.position && row.position <= CURVE_POSITIONS }
          curve = ctr_curve(rows).to_h
          rows.map do |row|
            CtrPoint.new(
              query: row[:query],
              position: row.position,
              ctr: row.ctr,
              clicks: row.clicks,
              impressions: row.impressions,
              expected: curve_at(curve, row.position)
            )
          end
        end
      end

      # Smoothed over the neighbouring positions, since few queries sit at
      # any one and a lone query would otherwise be its own curve.
      def ctr_curve(rows = ctr_points)
        (1..CURVE_POSITIONS).filter_map do |position|
          near = rows.select { |row| (row.position - position).abs <= 1 }
          impressions = near.sum(&:impressions)
          [position, near.sum(&:clicks).to_f / impressions] if impressions.positive?
        end
      end

      def below_curve(limit: 10)
        below = ctr_points.select(&:below?).sort_by { |point| [-point.impressions, point.query.to_s] }
        below.first(limit || below.size)
      end

      # Starting on Sunday, as GA's and Search Console's weeks do.
      def weekday_clicks(within = period)
        clicks = (within.from..within.to).zip(daily(:clicks, within)).to_h
        weeks = (within.from.beginning_of_week(:sunday)..within.to).step(7).to_a
        weeks.index_with { |start| (start...(start + 7)).map { |date| clicks[date] } }
      end

      def position_distribution(within = period)
        rows = queries(within).select(&:position)
        POSITION_BUCKETS.transform_values do |range|
          in_bucket = rows.select { |row| range.cover?(row.position) }
          {queries: in_bucket.size, clicks: in_bucket.sum(&:clicks), impressions: in_bucket.sum(&:impressions)}
        end
      end

      def pages(within = period)
        @pages ||= {}
        @pages[within.key] ||= Stat.grouped(within.apply(Stat.page_totals), by: [:page_path])
                                 .index_by { |row| row[:page_path] }
      end

      def page_queries(page_path, within = period, limit: 10)
        criteria = within.apply(Stat.by_query.per_page.where(page_path: page_path))
        Stat.grouped(criteria, by: [:query]).order(clicks: :desc, impressions: :desc).limit(limit).to_a
      end

      def page_totals(page_path, within = period)
        Stat.grouped(within.apply(Stat.page_totals.where(page_path: page_path)), by: []).totals
      end

      # Nil on days not synced, as the site's are; a synced day the page
      # wasn't shown is a real zero, and a position nobody saw is no position.
      def page_daily(page_path, within = period)
        rows = Stat.grouped(within.apply(Stat.page_totals.where(page_path: page_path)), by: [:date])
          .index_by(&:date)
        synced = days_with_data(within).to_set
        fields = %i[clicks impressions position]
        (within.from..within.to).each_with_object(fields.to_h { |field| [field, []] }) do |date, series|
          row = rows[date]
          fields.each do |field|
            series[field] << if row then row.value(field)
            elsif synced.include?(date) && field != :position then 0
            end
          end
        end
      end

      # The busiest few by clicks, the rest together, so the colours stay
      # few enough to tell apart. Nil on days not synced, as the site's are.
      def appearances_daily(within = period, limit: 4)
        rows = AppearanceStat.grouped(within.apply(AppearanceStat.site_wide), by: [:date, :appearance]).to_a
        totals = rows.each_with_object(Hash.new(0)) { |row, sums| sums[row[:appearance]] += row.clicks }
        top = totals.select { |_, clicks| clicks.positive? }.sort_by do |appearance, clicks|
          [-clicks, appearance]
        end.first(limit).map(&:first)
        synced = days_with_data(within).to_set
        series = Hash.new { |hash, key| hash[key] = Hash.new(0) }
        rows.each do |row|
          series[top.include?(row[:appearance]) ? row[:appearance] : :other][row.date] += row.clicks
        end
        [*top, (:other if series.key?(:other) && series[:other].values.sum.positive?)].compact.to_h do |key|
          [key, (within.from..within.to).map { |date| series[key][date] if synced.include?(date) }]
        end
      end

      def countries(within = period)
        criteria = within.apply(CountryStat.site_wide)
        CountryStat.grouped(criteria, by: [:country]).index_by { |row| row[:country] }
      end

      def devices(within = period)
        criteria = within.apply(DeviceStat.site_wide)
        DeviceStat.grouped(criteria, by: [:device]).index_by { |row| row[:device].to_s.capitalize }
      end

      def days_with_data(within = period)
        Stat.site_totals.where(date: within.from..within.to).distinct(:date).map(&:to_date)
      end

      def to_csv(export, blog_stats:)
        CSV.generate do |csv|
          case export
          when "queries", "opportunities"
            csv << ["Query", "Clicks", "Impressions", "CTR", "Position", "Position before"]
            rows = if export == "queries"
              queries.sort_by { |row| [-row.clicks, -row.impressions] }
            else
              opportunities(limit: nil)
            end
            rows.each do |row|
              before = previous_queries[row[:query]] if compared?
              csv << [
                row[:query],
                CompareChange.cell(row.clicks, before&.clicks, compare: compared?),
                CompareChange.cell(row.impressions, before&.impressions, compare: compared?),
                row.ctr.round(4),
                row.position&.round(1),
                previous_positions[row[:query]]&.round(1)
              ]
            end
          # Lost queries have no figures this period, so theirs are the period before's.
          when "new", "lost"
            csv << ["Query", "Clicks", "Impressions", "CTR", "Position"]
            rows = export == "new" ? new_queries(limit: nil) : lost_queries(limit: nil)
            rows.each do |row|
              csv << [row[:query], row.clicks, row.impressions, row.ctr.round(4), row.position&.round(1)]
            end
          when "pages"
            csv << ["Page", "Clicks", "Impressions", "CTR", "Position"]
            low_ctr_pages(limit: nil).each do |row|
              csv << [row[:page_path], row.clicks, row.impressions, row.ctr.round(4), row.position&.round(1)]
            end
          when "ctr"
            csv << ["Query", "Clicks", "Impressions", "CTR", "Position", "Usual CTR at position", "Well under usual"]
            ctr_points.sort_by { |point| [-point.impressions, point.query.to_s] }.each do |point|
              csv << [
                point.query,
                point.clicks,
                point.impressions,
                point.ctr.round(4),
                point.position.round(1),
                point.expected&.round(4),
                point.below? ? "Yes" : "No"
              ]
            end
          # A row per page, so the split can be sorted and summed.
          when "competing"
            csv << ["Query", "Page", "Clicks", "Impressions", "Share of query's impressions", "Position"]
            competing_queries(limit: nil).each do |row|
              row.pages.each do |page|
                csv << [
                  row.query,
                  page[:page_path],
                  page.clicks,
                  page.impressions,
                  (page.impressions.to_f / row.impressions).round(4),
                  page.position&.round(1)
                ]
              end
            end
          when "countries"
            csv << ["Country", "Clicks", "Impressions", "CTR", "Position", "Blog views"]
            views = blog_stats.by_country(:views)
            countries.values.sort_by { |row| -row.clicks }.each do |row|
              csv << [
                row[:country],
                row.clicks,
                row.impressions,
                row.ctr.round(4),
                row.position&.round(1),
                views.fetch(row[:country], 0)
              ]
            end
          end
        end
      end

      private

      # An average position is fractional, but the curve has whole ones only.
      def curve_at(curve, position)
        lower = curve.keys.select { |key| key <= position }.max
        upper = curve.keys.select { |key| key >= position }.min
        return curve[lower || upper] if lower.nil? || upper.nil? || lower == upper

        curve[lower] + (curve[upper] - curve[lower]) * (position - lower) / (upper - lower)
      end

      # Most seen first, since a query seen once is mostly noise.
      def by_impressions(rows, limit)
        rows.sort_by { |row| [-row.impressions, -row.clicks, row[:query].to_s] }.first(limit || rows.size)
      end

      def totals_criteria(within)
        code = within.country || country
        criteria = code ? CountryStat.site_wide.where(country: code) : Stat.site_totals
        within.apply(criteria)
      end
    end
  end
end
