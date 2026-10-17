# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from labels because an event's method says how it was done
    # (a plain click against a new-tab open), which its label doesn't.
    # Named event_method, since method is already every Ruby object's own.
    class EventMethodStat
      include Mongoid::Document
      include DailyStat

      field :page_path, type: String
      field :event_name, type: String
      field :event_method, type: String
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0
      field :key_events, type: Integer, default: 0

      key_fields :page_path, :event_name, :event_method

      index({date: 1, page_path: 1, event_name: 1, event_method: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      index({page_path: 1, date: 1})

      validates :page_path, :event_name, :event_method, presence: true

      class << self
        # Counted the way events are, so their totals read alike.
        def grouped(criteria, by:)
          EventStat.grouped(criteria, by: by)
        end
      end
    end
  end
end
