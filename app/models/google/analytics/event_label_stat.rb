# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from other events because the blog's click tracking names
    # only the kind of click, and its label is what says which share
    # button, social link or download it was. With the event's method too,
    # which says how it was done (a plain click against a new-tab open), so
    # one report holds both; each is "(not set)" on the rows that carry only
    # the other. Named event_method, since method is already every Ruby
    # object's own.
    class EventLabelStat
      include Mongoid::Document
      include DailyStat

      field :page_path, type: String
      field :event_name, type: String
      field :event_label, type: String, default: "(not set)"
      field :event_method, type: String, default: "(not set)"
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0
      field :key_events, type: Integer, default: 0

      # GA's filters for an event that carries a label, or a method; the
      # click tracking sends an empty label when an element has none.
      LABELLED = [["customEvent:event_label", "EXACT", "(not set)", true], ["customEvent:event_label", "EXACT", "", true]].freeze
      WITH_METHOD = [["customEvent:method", "EXACT", "(not set)", true], ["customEvent:method", "EXACT", "", true]].freeze
      UNSET = ["(not set)", ""].freeze

      key_fields :page_path, :event_name, :event_label, :event_method

      index({date: 1, page_path: 1, event_name: 1, event_label: 1, event_method: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      # Labels are only searched by substring, which no index helps.
      index({page_path: 1, date: 1})

      validates :page_path, :event_name, :event_label, :event_method, presence: true

      scope :labelled, -> { self.not.in(event_label: UNSET) }
      scope :with_method, -> { self.not.in(event_method: UNSET) }

      extend CountedAsEvents
    end
  end
end
