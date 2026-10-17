# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from other events because only a click carries the link it
    # led to, and which links readers follow says what they came for.
    class OutboundLinkStat
      include Mongoid::Document
      include DailyStat

      field :page_path, type: String
      field :link_url, type: String
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0
      field :key_events, type: Integer, default: 0

      key_fields :page_path, :link_url

      index({date: 1, page_path: 1, link_url: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      # Links are only searched by substring, which no index helps.
      index({page_path: 1, date: 1})

      validates :page_path, :link_url, presence: true

      class << self
        # Counted the way events are, so their totals read alike.
        def grouped(criteria, by:)
          EventStat.grouped(criteria, by: by)
        end
      end
    end
  end
end
