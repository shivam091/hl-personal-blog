# encoding: UTF-8

module Google
  module Analytics
    # Terms rather than single searches, since one reader retyping a term is
    # still one thing they looked for.
    class SiteSearch
      # Earlier days have no searches to count.
      COUNTED_SINCE = Date.new(2026, 10, 20)
      COUNTED = CountedSince.new(date: COUNTED_SINCE, what: "Searches", why: "when the blog's search began sending them")

      Term = Struct.new(:term, :searches, :not_found, keyword_init: true) do
        def not_found_share
          not_found.fdiv(searches) if searches.positive?
        end
      end

      attr_reader :period

      def initialize(period)
        @period = period
      end

      def any?
        SearchTermStat.exists?
      end

      # Nil without a comparison, or before any term was stored, so a
      # period that began tracking isn't set against nothing as if it were a
      # collapse.
      def previous
        return @previous if defined?(@previous)

        @previous = (SiteSearch.new(period.previous) if period.compare? && SearchTermStat.where(:date.lte => period.previous.from).exists?)
      end

      def previous_terms
        @previous_terms ||= previous&.terms&.index_by(&:term) || {}
      end

      def terms
        @terms ||= begin
          counts = SearchTermStat.grouped(period.apply(SearchTermStat.all), by: [:search_term, :event_name]).to_a
          counts.group_by { |row| row[:search_term] }.map do |term, rows|
            Term.new(
              term: term,
              searches: rows.sum(&:event_count),
              not_found: rows.select { |row| row[:event_name] == SearchTermStat::NOT_FOUND_EVENT }.sum(&:event_count)
            )
          end
        end
      end

      def searches
        terms.sum(&:searches)
      end

      def not_found_share
        searches.positive? ? terms.sum(&:not_found).fdiv(searches) : nil
      end

      def top_terms(limit: 20)
        terms.sort_by { |row| [-row.searches, row.term] }.first(limit || terms.size)
      end

      # What readers look for and the blog doesn't have: the posts worth
      # writing, or the words worth adding to existing ones.
      def not_found_terms(limit: 20)
        rows = terms.select { |row| row.not_found.positive? }
        rows.sort_by { |row| [-row.not_found, row.term] }.first(limit || rows.size)
      end

      def to_csv
        CSV.generate do |csv|
          csv << ["Search term", "Searches", "Found nothing", "Share found nothing"]
          top_terms(limit: nil).each do |row|
            before = previous_terms[row.term]
            csv << [row.term, CompareChange.cell(row.searches, before&.searches.to_i, compare: !previous.nil?),
              CompareChange.cell(row.not_found, before&.not_found.to_i, compare: !previous.nil?), row.not_found_share&.round(4)]
          end
        end
      end
    end
  end
end
