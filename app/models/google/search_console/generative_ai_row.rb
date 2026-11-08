# encoding: UTF-8

module Google
  module SearchConsole
    # A page, country or device of one uploaded Generative AI export, kept as
    # a row of its own so its list sorts and pages like any other.
    class GenerativeAiRow
      include Mongoid::Document

      BREAKDOWNS = %w[pages countries devices].freeze
      COUNTRY_CODES = YAML.load_file(Rails.root.join("config/country_names.yml")).freeze

      belongs_to :import, class_name: "Google::SearchConsole::GenerativeAiImport", inverse_of: :rows

      field :breakdown, type: String
      # A page's full URL, or a country or device as Google names it.
      field :label, type: String
      # A country's alpha-2 code, as every other stat codes countries, so it
      # reads as they do; none for a name Google spells some new way.
      field :country, type: String
      field :impressions, type: Integer, default: 0

      index({import_id: 1, breakdown: 1, impressions: -1})

      validates :breakdown, inclusion: {in: BREAKDOWNS}
      validates :label, presence: true

      def self.country_code(name)
        COUNTRY_CODES[name.to_s.strip]
      end
    end
  end
end
