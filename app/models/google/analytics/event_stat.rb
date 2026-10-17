# encoding: UTF-8

module Google
  module Analytics
    # Apart from the traffic breakdowns because events are counted per event,
    # not per visit. Finished reads carry their reading time, so it's kept
    # beside their count rather than in a report of its own.
    class EventStat
      include Mongoid::Document
      include DailyStat

      field :page_path, type: String
      field :event_name, type: String
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      # Kept beside active users because GA's own events report counts
      # users engaged or not.
      field :total_users, type: Integer, default: 0
      # Non-zero only for events marked as key events in GA.
      field :key_events, type: Integer, default: 0
      # Only article_read carries it; every other event's is 0.
      field :read_seconds, type: Integer, default: 0

      key_fields :page_path, :event_name

      index({date: 1, page_path: 1, event_name: 1}, {unique: true})
      # Every read is within a date range, so the range follows the match.
      index({page_path: 1, date: 1})
      index({event_name: 1, date: 1})

      validates :page_path, :event_name, presence: true

      ARTICLE_READ = "article_read"
      COUNTS = %i[event_count total_users active_users key_events read_seconds].freeze
      # Worked out from the summed counts, since a ratio can't be added up
      # across days.
      GROUP_DERIVED = {
        "event_count_per_active_user" => {"$cond" => [{"$gt" => ["$active_users", 0]}, {"$divide" => ["$event_count", "$active_users"]}, 0]}
      }.freeze

      class Total < GroupedScope::Row
        COUNTS.each do |count|
          define_method(count) { self[count].to_i }
        end

        # From the counts, so it follows GA's own users once they're merged in.
        def event_count_per_active_user
          active_users.zero? ? 0.0 : event_count.fdiv(active_users)
        end

        # Only ever GA's own, since a session spans days and pages; unknown
        # rather than zero when GA couldn't be asked.
        def sessions
          self[:sessions]&.to_i
        end

        def events_per_session
          return if sessions.nil?

          sessions.zero? ? 0.0 : event_count.fdiv(sessions)
        end
      end

      class << self
        # Any day's, so a page that was missing once still shows what linked
        # to it after it's been put back.
        # The first day the blog sent the event, or nil if it never has.
        def first_date(event_name)
          where(event_name: event_name).order(date: :asc).only(:date).first&.date
        end

        def paths_for(event_name)
          where(event_name: event_name).distinct(:page_path)
        end

        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: COUNTS.index_with { |count| "$#{count}" }, derived: GROUP_DERIVED, row_class: Total)
        end
      end
    end
  end
end
