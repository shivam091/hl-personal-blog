# encoding: UTF-8

module Mixpanel
  # What readers click on each page, from Mixpanel's autocapture, so a TOC,
  # a copy button or a tag can be judged without tagging each one. Only a
  # page's top few a day are kept, so the collection stays small.
  class ClickStat
    include Mongoid::Document
    include DailyStat

    TOP = 5
    # Below this a day's top five is mostly single clicks, which rank
    # nothing.
    MIN_PAGE_VIEWS = 10
    MAX_TARGET = 200

    field :page_path, type: String
    # The element ("a.toc-link → #grid-areas").
    field :target, type: String
    field :count, type: Integer, default: 0
    field :visitors, type: Integer, default: 0
    # Hashed, one per visitor, so a period's distinct visitors can be counted
    # rather than each day's added up; empty on rows synced before.
    field :visitor_ids, type: Array, default: []

    key_fields :page_path, :target

    index({date: 1, page_path: 1, target: 1}, {unique: true})
    index({page_path: 1, date: 1})

    validates :page_path, :target, presence: true
  end
end
