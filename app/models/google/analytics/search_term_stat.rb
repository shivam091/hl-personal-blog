# encoding: UTF-8

module Google
  module Analytics
    # What readers type into the blog's search, kept apart from other events
    # because only a search carries its term. The blog sends a search that
    # found nothing as its own event, so what readers look for and don't
    # find can be told from what they find.
    class SearchTermStat
      include Mongoid::Document
      include DailyStat

      FOUND_EVENT = "view_search_results"
      NOT_FOUND_EVENT = "search_no_results"
      EVENTS = [FOUND_EVENT, NOT_FOUND_EVENT].freeze

      field :search_term, type: String
      field :event_name, type: String
      field :event_count, type: Integer, default: 0
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0
      field :key_events, type: Integer, default: 0

      key_fields :search_term, :event_name

      index({date: 1, search_term: 1, event_name: 1}, {unique: true})

      validates :search_term, :event_name, presence: true

      extend CountedAsEvents
    end
  end
end
