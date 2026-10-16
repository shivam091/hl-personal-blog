# encoding: UTF-8

module Google
  module SearchConsole
    # Which posts to rewrite or retitle, worked out from the stored Search
    # Console figures: queries nearly on the first page, and pages losing
    # the clicks they used to get.
    class Opportunities
      # Just off the top spots to the second page, where a better post or
      # title moves a query furthest.
      STRIKING_POSITIONS = 4.5..20.5
      # The spot a query is measured against when guessing what it could earn.
      TARGET_POSITION = 3
      # A page needs this many clicks before to have lost them meaningfully.
      MIN_PREVIOUS_CLICKS = 10
      # And to have lost at least this share, so ordinary scatter isn't flagged.
      MIN_LOSS_SHARE = 0.2
      EXPORTS = {"striking" => "Striking distance", "losing" => "Pages losing clicks"}.freeze

      Query = Struct.new(
        :query, :page_path, :clicks, :impressions, :ctr, :position, :expected_ctr, :potential_clicks,
        :low_ctr, keyword_init: true
      )
      LosingPage = Struct.new(
        :page_path, :clicks, :previous_clicks, :impressions, :previous_impressions, :position,
        :previous_position, keyword_init: true
      ) do
        def lost
          previous_clicks - clicks
        end

        # The likeliest reason, so the fix is plain: a slipped ranking needs
        # a better post, fewer searches need nothing, a lower CTR a better title.
        def cause
          if position && previous_position && position - previous_position >= 1
            "Ranking dropped"
          elsif previous_impressions.positive? && impressions < previous_impressions * (1 - MIN_LOSS_SHARE)
            "Fewer searches"
          else
            "Fewer clicks per view"
          end
        end
      end

      attr_reader :period, :summary

      def initialize(period, summary: Summary.new(period))
        @period = period
        @summary = summary
      end

      def any?
        summary.any?
      end

      def previous_synced?
        summary.previous_synced?
      end

      # Measured against the site's own CTR for the third spot rather than an
      # industry figure, so the gain is one this blog could actually reach.
      def striking_distance(limit: 15)
        @striking_distance ||= begin
          points = summary.ctr_points.index_by(&:query)
          target = summary.ctr_curve.to_h[TARGET_POSITION]
          rows = summary.queries.select do |row|
            row.position && STRIKING_POSITIONS.cover?(row.position) && row.impressions >= Summary::MIN_IMPRESSIONS
          end
          pages = top_pages(rows.map { |row| row[:query] })
          rows.map do |row|
            point = points[row[:query]]
            Query.new(
              query: row[:query],
              page_path: pages[row[:query]],
              clicks: row.clicks,
              impressions: row.impressions,
              ctr: row.ctr,
              position: row.position,
              expected_ctr: point&.expected,
              low_ctr: point&.below? || false,
              potential_clicks: (target ? [(row.impressions * target - row.clicks).round, 0].max : nil)
            )
          end.sort_by { |row| [-row.potential_clicks.to_i, -row.impressions, row.query.to_s] }
        end
        @striking_distance.first(limit || @striking_distance.size)
      end

      def target_ctr
        summary.ctr_curve.to_h[TARGET_POSITION]
      end

      # Empty until the period before was synced, since every page would
      # otherwise read as having lost nothing.
      def losing_pages(limit: 15)
        return [] unless summary.queries_compared?

        @losing_pages ||= begin
          now = summary.pages
          summary.pages(period.previous).values.filter_map do |before|
            current = now[before[:page_path]]
            row = LosingPage.new(
              page_path: before[:page_path],
              clicks: current&.clicks.to_i,
              previous_clicks: before.clicks,
              impressions: current&.impressions.to_i,
              previous_impressions: before.impressions,
              position: current&.position,
              previous_position: before.position
              )
            row if row.previous_clicks >= MIN_PREVIOUS_CLICKS && row.lost >= row.previous_clicks * MIN_LOSS_SHARE
          end.sort_by { |row| [-row.lost, row.page_path.to_s] }
        end
        @losing_pages.first(limit || @losing_pages.size)
      end

      def to_csv(export)
        CSV.generate do |csv|
          case export
          when "losing"
            csv << [
              "Page", "Clicks", "Clicks before", "Lost", "Impressions", "Impressions before",
              "Position", "Position before", "Likely cause"
            ]
            losing_pages(limit: nil).each do |row|
              csv << [
                row.page_path, row.clicks, row.previous_clicks, row.lost, row.impressions, row.previous_impressions,
                row.position&.round(1), row.previous_position&.round(1), row.cause
              ]
            end
          else
            csv << [
              "Query", "Page", "Clicks", "Impressions", "CTR", "Position", "Usual CTR at position", "Low CTR",
              "Clicks to gain at position #{TARGET_POSITION}"
            ]
            striking_distance(limit: nil).each do |row|
              csv << [
                row.query, row.page_path, row.clicks, row.impressions, row.ctr.round(4), row.position.round(1),
                row.expected_ctr&.round(4), row.low_ctr ? "Yes" : "No", row.potential_clicks
              ]
            end
          end
        end
      end

      private

      # The page most shown for each query, the one a rewrite should go to.
      def top_pages(queries)
        return {} if queries.empty?

        criteria = period.apply(Stat.by_query.per_page.where(:query.in => queries))
        Stat
          .grouped(criteria, by: [:query, :page_path])
          .to_a
          .group_by { |row| row[:query] }
          .transform_values { |rows| rows.max_by { |row| [row.impressions, row.clicks] }[:page_path] }
      end
    end
  end
end
