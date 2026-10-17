# encoding: UTF-8

module Google
  module Analytics
    # So where readers come from can be read beside the blog's search
    # figures without opening Google Analytics.
    class AcquisitionController < ApplicationController
      include DailyReport

      # Worded as GA's own help defines them, so a figure means the same here
      # as there.
      USERS_HINT = "The number of distinct users who visited your website."
      KEY_EVENTS_HINT = "The number of times users triggered a key event."
      METRICS = [
        DailyReport::Metric.new(field: :views, label: "Views", format: :count, icon: "eye",
          hint: "The number of web pages your users saw. Repeated views of a single page are counted."),
        DailyReport::Metric.new(field: :active_users, label: "Active users", format: :count, icon: "users", hint: USERS_HINT),
        DailyReport::Metric.new(field: :views_per_active_user, label: "Views per active user", format: :ratio, icon: "eye",
          hint: "The average number of web pages viewed per active user (Views divided by Active users)."),
        DailyReport::Metric.new(field: :new_users, label: "New users", format: :count, icon: "plus",
          hint: "The number of users who visited your website for the first time."),
        DailyReport::Metric.new(field: :sessions, label: "Sessions", format: :count, icon: "activity",
          hint: "The number of sessions that began on your website."),
        DailyReport::Metric.new(field: :engaged_sessions, label: "Engaged sessions", format: :count, icon: "activity",
          hint: "The number of sessions that lasted longer than 10 seconds, had a key event, or had 2 or more page views."),
        DailyReport::Metric.new(field: :engagement_rate, label: "Engagement rate", format: :rate, icon: "trending-up",
          hint: "The percentage of sessions that were engaged sessions: ones that lasted longer than 10 seconds, " \
            "had a key event, or had 2 or more page views."),
        DailyReport::Metric.new(field: :engaged_sessions_per_active_user, label: "Engaged sessions per active user", format: :ratio,
          icon: "users", hint: "The average number of engaged sessions per active user (Engaged sessions divided by Active users)."),
        DailyReport::Metric.new(field: :average_engagement_seconds, label: "Engagement per user", format: :duration, icon: "clock",
          hint: "Average engagement time per active user: the average time your website was in focus in a user's browser."),
        DailyReport::Metric.new(field: :events_per_session, label: "Events per session", format: :ratio, icon: "mouse-pointer",
          hint: "The average number of events per session (Event count divided by Sessions)."),
        DailyReport::Metric.new(field: :event_count, label: "Event count", format: :count, icon: "mouse-pointer",
          hint: "The number of times users triggered an event."),
        DailyReport::Metric.new(field: :key_events, label: "Key events", format: :count, icon: "check-circle", hint: KEY_EVENTS_HINT,
          row_change: true)
      ].freeze
      # A reader or a visit spans days and pages, so these are GA's own counts
      # for the period rather than the stored rows added up.
      LIVE_METRICS = {active_users: "activeUsers", new_users: "newUsers", sessions: "sessions", engaged_sessions: "engagedSessions"}.freeze
      # As GA's own User acquisition report has them, so the two can be
      # checked against each other.
      USER_ACQUISITION_METRICS = METRICS.flat_map do |metric|
        case metric.field
        when :active_users
          [DailyReport::Metric.new(field: :total_users, label: "Total users", format: :count, icon: "users",
            hint: "The number of distinct users who have logged at least one event, regardless of whether the site was in use when that event was logged."),
            metric]
        when :new_users
          [metric, DailyReport::Metric.new(field: :returning_users, label: "Returning users", format: :count, icon: "rotate-ccw",
            hint: "The number of users who have initiated at least one previous session, regardless of whether or not the previous sessions were engaged sessions.")]
        else
          [metric]
        end
      end.freeze
      OWN_REFERRER = "//#{Analytics::SyncService::HOSTNAME}"
      # GA's own names for a session that carried no campaign.
      UNTAGGED_CAMPAIGNS = ["(direct)", "(organic)", "(referral)", "(not set)"].freeze
      BREAKDOWNS = {
        # Sorted by new users, as GA's own User acquisition report is, since
        # it's the readers a channel first brought in that it's credited with.
        "user-acquisition" => DailyReport::Breakdown.new(key: "user-acquisition", label: "User acquisition",
          keys: %i[first_channel_group first_source first_medium],
          headings: ["First user channel", "First user source", "First user medium"], criteria: -> { UserAcquisitionStat.all },
          default_sort: {"new_users" => "desc"}, chart_metric: :new_users, metrics: USER_ACQUISITION_METRICS,
          live_metrics: LIVE_METRICS.merge(total_users: "totalUsers"),
          search: [Filtering::Contains.new(:first_source, field: :first_source, label: "Source contains", placeholder: "e.g. google or t.co")]),
        "sources" => DailyReport::Breakdown.new(key: "sources", label: "Sources", keys: %i[channel_group source medium],
          headings: %w[Channel Source Medium], criteria: -> { SourceStat.all },
          search: [Filtering::Contains.new(:source, field: :source, label: "Source contains", placeholder: "e.g. google or t.co")]),
        # Only tagged visits, since every other session has GA's "(direct)"
        # or "(organic)" for a campaign, which Sources already splits.
        "campaigns" => DailyReport::Breakdown.new(key: "campaigns", label: "Campaigns", keys: %i[campaign source medium content],
          headings: ["Session campaign", "Source", "Medium", "Content"],
          criteria: -> { CampaignStat.not.in(campaign: UNTAGGED_CAMPAIGNS) },
          live_filters: UNTAGGED_CAMPAIGNS.map { |campaign| ["sessionCampaignName", "EXACT", campaign, true] },
          search: [Filtering::Contains.new(:campaign, field: :campaign, label: "Campaign contains", placeholder: "e.g. new_entry")]),
        # A reader moving between the blog's own pages isn't one it was
        # referred, so only other sites are counted.
        "referrers" => DailyReport::Breakdown.new(key: "referrers", label: "Referrers", keys: [:referrer], headings: ["Referrer"],
          criteria: -> { ReferrerStat.not.where(referrer: /#{Regexp.escape(OWN_REFERRER)}/i) },
          live_filters: [["pageReferrer", "CONTAINS", OWN_REFERRER, true]],
          search: [Filtering::Contains.new(:referrer, field: :referrer, label: "Referrer contains", placeholder: "e.g. reddit.com")])
      }.freeze
      # Shares as GA's own reports show them; views charted since they're what
      # every breakdown here counts.
      SHOW_SHARES = true
      CHART_METRIC = :views
      # So Event count and Key events can each be narrowed to one event, as in GA.
      EVENT_FILTERING = true
      EXPORT_NAME = "analytics-acquisition"
      LIST_LAYOUT = "analytics_acquisition"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"

      private

      # Only on Sources, since its rows are the channels the chart shares
      # out. Cut by the same period and search as its table, so the two agree.
      def load_page
        super
        @channel_mix = ChannelMix.new(@filtered, @period).shares if @breakdown.key == "sources"
      end
    end
  end
end
