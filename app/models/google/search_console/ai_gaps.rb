# encoding: UTF-8

module Google
  module SearchConsole
    # Search's figures are taken over the latest Generative AI upload's range,
    # the only days its page totals cover, so the two compare over the same days.
    class AiGaps
      # Below this, a page in AI answers is a stray mention rather than one
      # they lean on.
      MIN_AI_IMPRESSIONS = 10

      Row = Struct.new(:page_path, :ai_impressions, :clicks, :impressions, keyword_init: true)

      attr_reader :ai

      def initialize(ai)
        @ai = ai
      end

      def any?
        ai.covered.present?
      end

      def period
        Period.new({from: ai.covered.begin.iso8601, to: ai.covered.end.iso8601}) if any?
      end

      def shown_not_clicked(limit: 10)
        return [] unless any?

        rows = ai.pages.select { |_, impressions| impressions >= MIN_AI_IMPRESSIONS }.map { |path, impressions| row(path, impressions) }
        rows.sort_by { |row| [row.clicks.fdiv(row.ai_impressions), -row.ai_impressions, row.page_path] }.first(limit)
      end

      def missing_from_ai(limit: 10)
        return [] unless any?

        search_pages.values
          .select { |stat| stat.impressions >= Summary::MIN_IMPRESSIONS && ai.pages.fetch(stat[:page_path], 0).zero? }
          .sort_by { |stat| [-stat.impressions, stat[:page_path].to_s] }
          .first(limit)
          .map { |stat| row(stat[:page_path], 0) }
      end

      private

      def row(path, ai_impressions)
        stat = search_pages[path]
        Row.new(page_path: path, ai_impressions: ai_impressions, clicks: stat&.clicks.to_i, impressions: stat&.impressions.to_i)
      end

      def search_pages
        @search_pages ||= Summary.new(period).pages
      end
    end
  end
end
