# encoding: UTF-8

module Mixpanel
  # How each page was read, which GA can't say per view: how long readers
  # were actually active on it and how far down they got.
  class PageStat
    include Mongoid::Document
    include DailyStat

    # Far enough down to have read the piece, short of the footer and
    # related links that many never scroll past.
    READ_THROUGH_PERCENT = 90

    field :page_path, type: String
    field :content_group, type: String
    field :page_views, type: Integer, default: 0
    field :visitors, type: Integer, default: 0
    # Views the blog reported a page_leave for; a bounce with no time and no
    # scroll sends none, so these are the averages' base.
    field :engaged_views, type: Integer, default: 0
    field :engaged_seconds, type: Integer, default: 0
    field :scroll_percent_sum, type: Integer, default: 0
    field :read_through_views, type: Integer, default: 0
    field :rage_clicks, type: Integer, default: 0
    field :dead_clicks, type: Integer, default: 0
    field :js_errors, type: Integer, default: 0

    key_fields :page_path

    index({date: 1, page_path: 1}, {unique: true})
    index({page_path: 1, date: 1})

    validates :page_path, presence: true
  end
end
