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
    # The quarters the blog's own scroll_depth events use, so the two agree.
    SCROLL_MILESTONES = [25, 50, 75, 100].freeze
    # Cut where a glance turns into a skim, a read and a close read, so
    # skimmers and readers are counted apart.
    READING_TIMES = {
      "under_15" => ["Under 15s", 15],
      "15_60" => ["15–60s", 60],
      "60_180" => ["1–3 min", 180],
      "over_180" => ["3+ min", nil]
    }.freeze

    def self.reading_time(seconds)
      READING_TIMES.find { |_, (_, below)| below.nil? || seconds < below }.first
    end

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
    # Visitors by whether GA loaded for them, so GA's figures for this page
    # can be scaled up by what it missed; blockers aren't spread evenly
    # across topics.
    field :ga_statuses, type: Hash, default: {}
    # Out of engaged_views, so they share a base with the averages above.
    field :scroll_reached, type: Hash, default: {}
    field :reading_times, type: Hash, default: {}
    # A few rather than every replay, so the row stays small; Mixpanel
    # keeps the rest.
    field :replays, type: Array, default: []

    key_fields :page_path

    index({date: 1, page_path: 1}, {unique: true})
    index({page_path: 1, date: 1})

    validates :page_path, presence: true
  end
end
