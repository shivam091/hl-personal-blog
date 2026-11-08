# encoding: UTF-8

module Google
  module SearchConsole
    # One uploaded export of the Generative AI report. Its days go into the
    # daily stats, where a later upload's figures replace an earlier one's,
    # since Google settles recent days late. Its pages, countries and
    # devices are each a total over the whole export, with no days to split
    # them by, so they're kept as the upload had them, dated by its range.
    class GenerativeAiImport
      include Mongoid::Document
      include Mongoid::Timestamps

      field :filename, type: String
      field :search_type, type: String
      field :from, type: Date
      field :to, type: Date
      # What the upload did to the daily stats, for the notice and the record.
      field :created_days, type: Integer, default: 0
      field :updated_days, type: Integer, default: 0

      has_many :rows, class_name: "Google::SearchConsole::GenerativeAiRow", inverse_of: :import, dependent: :delete_all

      index({search_type: 1, created_at: -1})

      validates :search_type, :from, :to, presence: true

      scope :latest_first, -> { order(created_at: :desc, _id: :desc) }

      # The workbook has already checked every figure, so a day failing here
      # is the database's doing; the upload isn't recorded then, so its
      # breakdowns never stand beside days that didn't go in.
      def self.record(workbook, filename:)
        days = workbook.daily.map { |date, impressions| {date: date, search_type: workbook.search_type, impressions: impressions} }
        result = GenerativeAiStat.sync(days, scope: GenerativeAiStat.where(search_type: workbook.search_type))
        raise GenerativeAiWorkbook::Error, "Some days couldn't be saved: #{result.errors.to_sentence}" if result.errors.any?

        create!(filename: filename, search_type: workbook.search_type, from: workbook.from, to: workbook.to,
          created_days: result.created, updated_days: result.updated).tap do |import|
          rows = GenerativeAiRow::BREAKDOWNS.flat_map do |breakdown|
            workbook.public_send(breakdown).map do |label, impressions|
              {import_id: import.id, breakdown: breakdown, label: label.to_s, impressions: impressions,
               country: (GenerativeAiRow.country_code(label) if breakdown == "countries")}.compact
            end
          end
          GenerativeAiRow.collection.insert_many(rows) if rows.any?
        end
      end
    end
  end
end
