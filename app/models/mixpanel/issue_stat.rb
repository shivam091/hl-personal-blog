# encoding: UTF-8

module Mixpanel
  # Where readers ran into trouble: an element clicked over and over, a click
  # that did nothing, or a script error. Kept per element or message, since
  # a count per page says something is wrong but not what.
  class IssueStat
    include Mongoid::Document
    include DailyStat

    KINDS = {
      "rage_click" => "Rage clicks",
      "dead_click" => "Dead clicks",
      "js_error" => "Script errors"
    }.freeze
    MAX_TARGET = 200

    field :kind, type: String
    field :page_path, type: String
    # The element ("button#share.icon → /feed.xml") or the error message.
    field :target, type: String
    field :count, type: Integer, default: 0
    field :visitors, type: Integer, default: 0
    # Hashed, one per visitor, so a period's distinct visitors can be counted
    # rather than each day's added up; empty on rows synced before.
    field :visitor_ids, type: Array, default: []
    # A few sessions where it happened, so the moment can be watched rather
    # than guessed at from the element's name.
    field :replays, type: Array, default: []

    key_fields :kind, :page_path, :target

    index({date: 1, kind: 1, page_path: 1, target: 1}, {unique: true})
    index({kind: 1, date: 1})

    validates :kind, inclusion: {in: KINDS.keys}
    validates :page_path, :target, presence: true
  end
end
