# encoding: UTF-8

module Google
  module Analytics
    # So every Google Analytics traffic breakdown carries the same counts and
    # one breakdown can be read against another row for row.
    module Traffic
      extend ActiveSupport::Concern

      COUNTS = %i[views active_users new_users sessions engaged_sessions engagement_seconds event_count key_events].freeze
      GROUP_SUMS = COUNTS.index_with { |count| "$#{count}" }.freeze
      # Per active user, so it matches the figure GA itself shows.
      GROUP_DERIVED = {
        "engagement_rate" => {"$cond" => [{"$gt" => ["$sessions", 0]}, {"$divide" => ["$engaged_sessions", "$sessions"]}, 0]},
        "average_engagement_seconds" => {"$cond" => [{"$gt" => ["$active_users", 0]}, {"$divide" => ["$engagement_seconds", "$active_users"]}, 0]},
        "views_per_active_user" => {"$cond" => [{"$gt" => ["$active_users", 0]}, {"$divide" => ["$views", "$active_users"]}, 0]},
        "engaged_sessions_per_active_user" => {"$cond" => [{"$gt" => ["$active_users", 0]}, {"$divide" => ["$engaged_sessions", "$active_users"]}, 0]},
        "events_per_session" => {"$cond" => [{"$gt" => ["$sessions", 0]}, {"$divide" => ["$event_count", "$sessions"]}, 0]},
        "average_engagement_seconds_per_session" => {"$cond" => [{"$gt" => ["$sessions", 0]}, {"$divide" => ["$engagement_seconds", "$sessions"]}, 0]}
      }.freeze

      class Total < GroupedScope::Row
        (COUNTS - %i[engagement_seconds]).each do |count|
          define_method(count) { self[count].to_i }
        end

        def engagement_seconds
          self[:engagement_seconds].to_f
        end

        # From the counts rather than the grouped fields, so they follow any
        # count GA gave in place of a summed one.
        def engagement_rate
          sessions.zero? ? 0.0 : engaged_sessions.fdiv(sessions)
        end

        def average_engagement_seconds
          active_users.zero? ? 0.0 : engagement_seconds.fdiv(active_users)
        end

        def views_per_active_user
          active_users.zero? ? 0.0 : views.fdiv(active_users)
        end

        def engaged_sessions_per_active_user
          active_users.zero? ? 0.0 : engaged_sessions.fdiv(active_users)
        end

        # Over every event even when Event count is narrowed to one, so
        # narrowing the events shown doesn't shrink how busy a session looks.
        def events_per_session
          sessions.zero? ? 0.0 : (self[:every_event_count] || event_count).to_i.fdiv(sessions)
        end

        def average_engagement_seconds_per_session
          sessions.zero? ? 0.0 : engagement_seconds.fdiv(sessions)
        end
      end

      included do
        include DailyStat

        # Path only, because that's how GA names pages.
        field :page_path, type: String
        field :views, type: Integer, default: 0
        field :active_users, type: Integer, default: 0
        field :new_users, type: Integer, default: 0
        field :sessions, type: Integer, default: 0
        field :engaged_sessions, type: Integer, default: 0
        field :engagement_seconds, type: Float, default: 0.0
        field :event_count, type: Integer, default: 0
        field :key_events, type: Integer, default: 0

        # Every read is within a date range, so the range follows the match.
        index({page_path: 1, date: 1})

        validates :page_path, presence: true
      end

      class_methods do
        # Only fields matched exactly get an index of their own: the rest are
        # searched by substring or grouped, which no index helps, and each
        # index slows the sync's bulk writes.
        def breakdown(*fields, filtered: [])
          key_fields :page_path, *fields
          index({date: 1, page_path: 1, **fields.index_with(1)}, {unique: true})
          Array(filtered).each { |field| index({field => 1, date: 1}) }
          validates(*fields, presence: true) if fields.any?
        end

        def grouped(criteria, by:)
          GroupedScope.new(criteria, keys: by, sums: GROUP_SUMS, derived: GROUP_DERIVED, row_class: Total)
        end
      end

      # Rates are worked out from the counts rather than stored, because a rate
      # can't be added up across days or pages and the counts behind it can.
      def engagement_rate
        sessions.zero? ? 0.0 : engaged_sessions.fdiv(sessions)
      end

      def bounce_rate
        sessions.zero? ? 0.0 : 1 - engagement_rate
      end
    end
  end
end
