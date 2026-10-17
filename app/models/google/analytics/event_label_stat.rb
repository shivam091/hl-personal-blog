# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from other events because the blog's click tracking names
    # only the kind of click, and its label is what says which share
    # button, social link or download it was.
    class EventLabelStat
      include Mongoid::Document
      include DailyStat

      field :page_path, type: String
      field :event_name, type: String
      field :event_label, type: String
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0
      field :key_events, type: Integer, default: 0

      key_fields :page_path, :event_name, :event_label

      index({date: 1, page_path: 1, event_name: 1, event_label: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      # Labels are only searched by substring, which no index helps.
      index({page_path: 1, date: 1})

      validates :page_path, :event_name, :event_label, presence: true

      class << self
        # Counted the way events are, so their totals read alike.
        def grouped(criteria, by:)
          EventStat.grouped(criteria, by: by)
        end
      end
    end
  end
end
