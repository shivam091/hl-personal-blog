# encoding: UTF-8

module Google
  module SearchConsole
    # Impressions only because Google gives no clicks and keeps AI Overviews
    # and AI Mode together; kept per search type since each is its own report
    # there.
    class GenerativeAiStat
      include Mongoid::Document
      include DailyStat

      field :search_type, type: String
      field :impressions, type: Integer, default: 0

      key_fields :search_type

      index({search_type: 1, date: 1}, {unique: true})

      validates :search_type, presence: true
      validates :impressions, numericality: {only_integer: true, greater_than_or_equal_to: 0}

      # Later uploads replace earlier figures since Google settles recent days
      # late; a failing day raises before the breakdowns are replaced so they
      # never stand beside days that didn't go in.
      def self.record(workbook)
        days = workbook.daily.map { |date, impressions| {date: date, search_type: workbook.search_type, impressions: impressions} }
        sync(days, scope: where(search_type: workbook.search_type)).tap do |result|
          raise GenerativeAiWorkbook::Error, "Some days couldn't be saved: #{result.errors.to_sentence}" if result.errors.any?
        end
      end

      def self.search_types
        distinct(:search_type).sort_by { |type| [-where(search_type: type).count, type] }
      end
    end
  end
end
