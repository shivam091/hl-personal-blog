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
    # Each step counts the day's visitors who also took every step before
    # it, so the steps only narrow. On one day rather than in order, since a
    # reader may subscribe from the footer before reading to the end.
    FUNNEL_STEPS = {
      "viewed" => ["Viewed a page", ["$mp_web_page_view"]],
      "read" => ["Read an article to the end", ["article_read"]],
      "form_seen" => ["Saw the newsletter form", ["newsletter_form_seen"]],
      "form_started" => ["Started typing an email", ["newsletter_form_started"]],
      "subscribed" => ["Subscribed", ["newsletter_subscribe"]]
    }.freeze
    # Counted apart rather than narrowed, since an error branches off
    # submitting and a retry can follow it.
    FORM_STEPS = {
      "seen" => ["Saw the form", "newsletter_form_seen"],
      "focused" => ["Focused the email field", "newsletter_form_focused"],
      "started" => ["Typed an email", "newsletter_form_started"],
      "submitted" => ["Submitted", "newsletter_form_submitted"],
      "error" => ["Got an error", "newsletter_form_error"],
      "subscribed" => ["Subscribed", "newsletter_subscribe"]
    }.freeze
    # The blog names a subscriber by a keyed hash of their email with this
    # prefix, so one reader can be followed from day to day without the
    # address ever reaching Mixpanel or here.
    READER_PREFIX = "reader_"

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
    field :funnel, type: Hash, default: {}
    # Visitors by what their system asks for, beside the theme they picked.
    field :reduced_motion, type: Hash, default: {}
    field :color_schemes, type: Hash, default: {}
    field :form_steps, type: Hash, default: {}
    field :form_errors, type: Array, default: []
    # Subscriber ids rather than counts, since whether a subscriber came
    # back is only known by finding them again on a later day.
    field :new_subscribers, type: Array, default: []
    # Pages opened earlier the same day by the device that subscribed, as
    # path and count pairs, since a path's dots can't be a key.
    field :subscriber_reads, type: Array, default: []
    field :returning_subscribers, type: Array, default: []

    key_fields

    index({date: 1}, {unique: true})
  end
end
