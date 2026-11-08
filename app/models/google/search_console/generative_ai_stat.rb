# encoding: UTF-8

module Google
  module SearchConsole
    # How often the blog showed up in AI Overviews and AI Mode each day, as
    # Search Console's Generative AI report counts it. Google keeps the two
    # together and gives no clicks, so impressions are all there is. Kept per
    # search type, since each is its own report there.
    class GenerativeAiStat
      include Mongoid::Document
      include DailyStat

      field :search_type, type: String
      field :impressions, type: Integer, default: 0

      key_fields :search_type

      index({search_type: 1, date: 1}, {unique: true})

      validates :search_type, presence: true
      validates :impressions, numericality: {only_integer: true, greater_than_or_equal_to: 0}

      # Most kept first, so the page opens on the report with the most days.
      def self.search_types
        distinct(:search_type).sort_by { |type| [-where(search_type: type).count, type] }
      end
    end
  end
end
