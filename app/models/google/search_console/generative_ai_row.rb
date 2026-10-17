# encoding: UTF-8

module Google
  module SearchConsole
    class GenerativeAiRow
      include Mongoid::Document

      BREAKDOWNS = %w[pages countries devices].freeze

      field :search_type, type: String
      # Google totals the breakdowns over the export's whole range and gives
      # no days, so the range is all that dates them.
      field :from, type: Date
      field :to, type: Date
      field :breakdown, type: String
      field :label, type: String
      # A country's alpha-2 code, as every other stat codes countries, so it
      # reads as they do; none for a name Google spells some new way.
      field :country, type: String
      field :impressions, type: Integer, default: 0

      index({search_type: 1, breakdown: 1, impressions: -1})

      validates :search_type, :from, :to, presence: true
      validates :breakdown, inclusion: {in: BREAKDOWNS}
      validates :label, presence: true

      def self.country_code(name)
        CountryCodes.from_name(name)
      end

      # Only the latest upload's are kept, since totals over different
      # ranges can't be added together or told apart in one list.
      def self.replace(workbook)
        rows = BREAKDOWNS.flat_map do |breakdown|
          workbook.public_send(breakdown).map do |label, impressions|
            {search_type: workbook.search_type, from: workbook.from, to: workbook.to, breakdown: breakdown, label: label.to_s,
             impressions: impressions, country: (country_code(label) if breakdown == "countries")}.compact
          end
        end
        where(search_type: workbook.search_type).delete_all
        collection.insert_many(rows) if rows.any?
      end
    end
  end
end
