# encoding: UTF-8

module Google
  module Analytics
    # Whether an event happens on phones or desktops, which EventStat,
    # stored by page alone, can't give.
    class EventDeviceStat
      include Mongoid::Document
      include DailyStat

      field :page_path, type: String
      field :event_name, type: String
      # Named as DeviceStat names devices, so the two line up.
      field :device, type: String
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0
      field :key_events, type: Integer, default: 0

      key_fields :page_path, :event_name, :device

      index({date: 1, page_path: 1, event_name: 1, device: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      index({page_path: 1, date: 1})
      index({event_name: 1, date: 1})
      index({device: 1, date: 1})

      validates :page_path, :event_name, :device, presence: true

      class << self
        # Summed and worked out as EventStat's are, so a row reads the same
        # split or not.
        def grouped(criteria, by:)
          EventStat.grouped(criteria, by: by)
        end
      end
    end
  end
end
