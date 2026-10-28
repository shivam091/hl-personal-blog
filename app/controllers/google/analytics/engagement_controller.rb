# encoding: UTF-8

module Google
  module Analytics
    # Exists because page views alone can't tell how far posts hold their
    # readers or which posts readers arrive on.
    class EngagementController < ApplicationController
      include DailyReport

      # As GA's Landing page report has them: a session has one landing page,
      # so sessions lead.
      LANDING_PAGE_METRICS = [
        DailyReport::Metric.new(field: :sessions, label: "Sessions", format: :count, icon: "activity",
          hint: "The number of sessions that began on your website."),
        DailyReport::Metric.new(field: :active_users, label: "Active users", format: :count, icon: "users", hint: AcquisitionController::USERS_HINT),
        DailyReport::Metric.new(field: :new_users, label: "New users", format: :count, icon: "plus",
          hint: "The number of users who interacted with your site for the first time."),
        DailyReport::Metric.new(field: :average_engagement_seconds_per_session, label: "Average engagement time per session",
          format: :duration, icon: "clock", hint: "The average time your website was in focus in a user's browser, per session."),
        DailyReport::Metric.new(field: :key_events, label: "Key events", format: :count, icon: "check-circle",
          hint: AcquisitionController::KEY_EVENTS_HINT, row_change: true)
      ].freeze

      # As GA's Pages and screens report has them, but by page path rather
      # than title: the site's titles lag a client-side navigation, so GA
      # files some pages under the title of the one before. With
      # Acquisition's session figures too, which GA keeps out of this report,
      # so a page's visits read beside its views.
      PAGE_METRICS = [
        *AcquisitionController::METRICS.index_by(&:field)
          .values_at(:views, :active_users, :views_per_active_user, :new_users, :sessions, :engaged_sessions, :engagement_rate,
            :engaged_sessions_per_active_user),
        DailyReport::Metric.new(field: :average_engagement_seconds, label: "Average engagement time per active user", format: :duration,
          icon: "clock", hint: "The average time your website was in focus in a user's browser, per active user."),
        *AcquisitionController::METRICS.index_by(&:field).values_at(:events_per_session, :event_count, :key_events)
      ].freeze

      # As GA's Key events report has them, so the two can be checked
      # against each other.
      KEY_EVENT_METRICS = [
        DailyReport::Metric.new(field: :key_events, label: "Key events", format: :count, icon: "check-circle",
          hint: AcquisitionController::KEY_EVENTS_HINT),
        DailyReport::Metric.new(field: :total_users, label: "Total users", format: :count, icon: "users",
          hint: "The number of distinct users who have logged at least one event, regardless of whether the site was in use when that event was logged."),
        DailyReport::Metric.new(field: :active_users, label: "Active users", format: :count, icon: "users", hint: AcquisitionController::USERS_HINT)
      ].freeze

      # Clicks rather than Event count, since every row is one click event.
      OUTBOUND_LINK_METRICS = [
        DailyReport::Metric.new(field: :event_count, label: "Clicks", format: :count, icon: "mouse-pointer",
          hint: "The number of times users clicked a link that led away from the site."),
        DailyReport::Metric.new(field: :total_users, label: "Total users", format: :count, icon: "users",
          hint: "The number of distinct users who clicked the link."),
        DailyReport::Metric.new(field: :active_users, label: "Active users", format: :count, icon: "users", hint: AcquisitionController::USERS_HINT)
      ].freeze

      BREAKDOWNS = {
        "events" => DailyReport::Breakdown.new(key: "events", label: "Events", keys: [:event_name], headings: ["Event"],
          criteria: -> { EventStat.all },
          search: [Filtering::Contains.new(:event, field: :event_name, label: "Event contains", placeholder: "e.g. scroll")]),
        # Only events marked as key events, and GA's users for those alone, so
        # the Total row isn't every event's.
        "key-events" => DailyReport::Breakdown.new(key: "key-events", label: "Key events", keys: [:event_name], headings: ["Key event"],
          criteria: -> { EventStat.where(:key_events.gt => 0) }, metrics: KEY_EVENT_METRICS, chart_metric: :key_events,
          live_metrics: {total_users: "totalUsers", active_users: "activeUsers"}, live_filters: [["isKeyEvent", "EXACT", "true"]],
          search: [Filtering::Contains.new(:event, field: :event_name, label: "Event contains", placeholder: "e.g. sign_up")]),
        # By event too, since one page's different events can't be added up.
        "pages" => DailyReport::Breakdown.new(key: "pages", label: "Events by page", keys: %i[event_name page_path],
          headings: %w[Event Page], criteria: -> { EventStat.all },
          search: [Filtering::Contains.new(:event, field: :event_name, label: "Event contains", placeholder: "e.g. scroll")]),
        # Every event on a page together, which page traffic doesn't store.
        "pages-and-screens" => DailyReport::Breakdown.new(key: "pages-and-screens", label: "Pages and screens", keys: [:page_path],
          headings: ["Page path"], criteria: -> { Stat.all }, metrics: PAGE_METRICS, live_metrics: AcquisitionController::LIVE_METRICS,
          chart_metric: :views, merged: {criteria: -> { EventStat.all }, fields: %i[event_count]}),
        # GA's own grouping for the same report, kept beside the paths since
        # a page that sent the wrong title only shows up when the two are
        # compared.
        "page-titles" => DailyReport::Breakdown.new(key: "page-titles", label: "Page titles", keys: [:page_title],
          headings: ["Page title and screen class"], criteria: -> { PageTitleStat.all }, metrics: PAGE_METRICS,
          live_metrics: AcquisitionController::LIVE_METRICS, chart_metric: :views,
          search: [Filtering::Contains.new(:page_title, field: :page_title, label: "Title contains", placeholder: "e.g. CSS Grid")]),
        "outbound-links" => DailyReport::Breakdown.new(key: "outbound-links", label: "Outbound links", keys: [:link_url],
          headings: ["Link URL"], criteria: -> { OutboundLinkStat.all }, metrics: OUTBOUND_LINK_METRICS, chart_metric: :event_count,
          live_metrics: {total_users: "totalUsers", active_users: "activeUsers"},
          search: [Filtering::Contains.new(:link_url, field: :link_url, label: "Link contains", placeholder: "e.g. github.com")]),
        # By event too, since a label like "posts" means one thing on Show
        # more and another on Share.
        "event-labels" => DailyReport::Breakdown.new(key: "event-labels", label: "Event labels", keys: %i[event_name event_label],
          headings: ["Event", "Event label"], criteria: -> { EventLabelStat.all },
          live_metrics: {total_users: "totalUsers", active_users: "activeUsers"},
          search: [Filtering::Contains.new(:event, field: :event_name, label: "Event contains", placeholder: "e.g. share"),
            Filtering::Contains.new(:event_label, field: :event_label, label: "Label contains", placeholder: "e.g. GitHub")]),
        "landing-pages" => DailyReport::Breakdown.new(key: "landing-pages", label: "Landing page", keys: [:page_path],
          headings: ["Landing page"], criteria: -> { LandingPageStat.all }, metrics: LANDING_PAGE_METRICS,
          live_metrics: {sessions: "sessions", active_users: "activeUsers", new_users: "newUsers"}, chart_metric: :sessions)
      }.freeze
      METRICS = [
        DailyReport::Metric.new(field: :event_count, label: "Event count", format: :count, icon: "mouse-pointer",
          hint: "The number of times users triggered an event."),
        DailyReport::Metric.new(field: :total_users, label: "Total users", format: :count, icon: "users",
          hint: "The number of distinct users who have logged at least one event, regardless of whether the site was in use when that event was logged."),
        DailyReport::Metric.new(field: :active_users, label: "Active users", format: :count, icon: "users", hint: AcquisitionController::USERS_HINT),
        DailyReport::Metric.new(field: :event_count_per_active_user, label: "Event count per active user", format: :ratio, icon: "activity",
          hint: "The average number of events per active user (Event count divided by Active users)."),
        DailyReport::Metric.new(field: :events_per_session, label: "Events per session", format: :ratio, icon: "activity",
          hint: "The average number of events per session (Event count divided by Sessions)."),
        DailyReport::Metric.new(field: :key_events, label: "Key events", format: :count, icon: "check-circle",
          hint: AcquisitionController::KEY_EVENTS_HINT, row_change: true)
      ].freeze
      # Figures that add up are read as each row's share of the whole, as GA's
      # own reports do.
      SHOW_SHARES = true
      CHART_METRIC = :event_count
      # So Event count and Key events can each be narrowed to one event, as in GA.
      EVENT_FILTERING = true
      # A reader triggers events over many days and pages, so these are GA's
      # own counts for the period rather than the stored rows added up.
      LIVE_METRICS = {total_users: "totalUsers", active_users: "activeUsers", sessions: "sessions"}.freeze
      EXPORT_NAME = "analytics-engagement"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"
      # The blog's own reader events, named as it sends them, so what readers
      # do on a page reads apart from GA's automatic events.
      READER_INTERACTIONS = {
        "article_read" => "Finished reading", "like" => "Liked", "copy_code" => "Copied code", "toc_click" => "Used the contents",
        "related_click" => "Opened a related entry", "prev_next_click" => "Went to the previous or next entry",
        "article_link_click" => "Followed a link in an entry", "search_result_click" => "Opened a search result",
        "sandbox_run" => "Ran a sandbox", "sandbox_reset" => "Reset a sandbox", "sandbox_download" => "Downloaded a sandbox",
        "sandbox_open_external" => "Opened a sandbox elsewhere", "page_not_found" => "Hit a missing page"
      }.freeze

      private

      # Only on the events tab, whose rows they're a summary of.
      def load_page
        super
        return unless @breakdown.key == "events"

        criteria = @filtering.apply(@period.apply(EventStat.where(:event_name.in => READER_INTERACTIONS.keys)))
        @interactions = EventStat.grouped(criteria, by: [:event_name]).to_h { |row| [row[:event_name], row.event_count] }
        @interaction_views = Stat.grouped(@filtering.apply(@period.apply(Stat.all)), by: []).totals.views
      end
    end
  end
end
