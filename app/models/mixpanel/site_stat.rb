# encoding: UTF-8

module Mixpanel
  # The day as a whole, including what only Mixpanel can see: how many of
  # its readers had GA blocked, and so are missing from every GA report.
  class SiteStat
    include Mongoid::Document
    include DailyStat

    # As the blog registers them; "off" is a reader whose page never started
    # gtag at all, "unknown" one whose events all came before the check.
    GA_STATUSES = %w[loaded blocked off unknown].freeze

    field :visitors, type: Integer, default: 0
    field :page_views, type: Integer, default: 0
    # Sessions with a replay recorded, to see how much of the plan's replay
    # allowance is being used.
    field :replays, type: Integer, default: 0
    # Visitors by status and theme. Event names are kept as pairs rather than
    # a hash, since Mixpanel's own start with "$", which a key can't.
    field :ga_statuses, type: Hash, default: {}
    field :themes, type: Hash, default: {}
    field :events, type: Array, default: []

    key_fields

    index({date: 1}, {unique: true})
  end
end
