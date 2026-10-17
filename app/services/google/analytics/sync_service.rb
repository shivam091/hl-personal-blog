# encoding: UTF-8

module Google
  module Analytics
    # The last few days are fetched again on every run because GA keeps
    # processing late hits for up to two days.
    class SyncService
      include Connected

      SCOPE = "https://www.googleapis.com/auth/analytics.readonly"
      REPORT_URL = "https://analyticsdata.googleapis.com/v1beta/properties/%{property}:runReport"
      DEFAULT_DAYS = 120
      # The API's maximum page size, so a big report takes as few requests as
      # it can.
      ROW_LIMIT = 100_000
      TRAFFIC_METRICS = {
        views: "screenPageViews", active_users: "activeUsers", new_users: "newUsers", sessions: "sessions",
        engaged_sessions: "engagedSessions", engagement_seconds: "userEngagementDuration", event_count: "eventCount", key_events: "keyEvents"
      }.freeze
      EVENT_METRICS = {event_count: "eventCount", active_users: "activeUsers", key_events: "keyEvents", total_users: "totalUsers"}.freeze
      FLOAT_METRICS = %i[engagement_seconds value_sum].freeze
      REPORTS = [
        # Split by title and new vs returning too, so the reports read by
        # either come from these rows rather than copies of them.
        {model: Stat, dimensions: {page_path: "pagePath", page_title: "unifiedScreenClass", visitor_type: "newVsReturning"}},
        # GA has no metric for returning users, so they're its active users
        # in returning sessions, as its own User acquisition report counts them.
        # With the first campaign too, so first-user campaigns are read from
        # the same rows rather than a second copy of every first source.
        {model: UserAcquisitionStat, dimensions: {page_path: "pagePath", first_channel_group: "firstUserDefaultChannelGroup",
          first_source: "firstUserSource", first_medium: "firstUserMedium", first_campaign: "firstUserCampaignName"},
          metrics: TRAFFIC_METRICS.merge(total_users: "totalUsers"),
          extra: [{metrics: {returning_users: "activeUsers"}, filters: [["newVsReturning", "EXACT", "returning"]]}]},
        # With the campaign and ad content too, so Campaigns is read from the
        # same rows rather than a second copy of every session source.
        {model: SourceStat, dimensions: {page_path: "pagePath", channel_group: "sessionDefaultChannelGroup", source: "sessionSource",
          medium: "sessionMedium", campaign: "sessionCampaignName", content: "sessionManualAdContent"}},
        {model: LandingSourceStat, dimensions: {page_path: "landingPage", channel_group: "sessionDefaultChannelGroup", source: "sessionSource",
          medium: "sessionMedium"}},
        # The rolling actives asked apart, since GA takes at most ten metrics
        # a report.
        {model: SiteDayStat, dimensions: {}, extra: [{metrics: SiteDayStat::ROLLING, filters: []}]},
        # Where readers came from and what with, in one report: a page's
        # readers a day mostly share a device, place and referrer, so one
        # row holds what four reports split by each would repeat.
        {model: AudienceStat, dimensions: {page_path: "pagePath", device: "deviceCategory", country: "countryId", region: "region",
          city: "city", referrer: "pageReferrer"}},
        {model: TechnologyStat, dimensions: {browser: "browser", operating_system: "operatingSystem"}},
        {model: LanguageStat, dimensions: {language: "language"}},
        {model: ScreenResolutionStat, dimensions: {screen_resolution: "screenResolution"}},
        # Empty unless Google signals is on.
        {model: AgeStat, dimensions: {age_bracket: "userAgeBracket"}},
        {model: GenderStat, dimensions: {gender: "userGender"}},
        {model: TimeOfDayStat, dimensions: {day_of_week: "dayOfWeek", hour: "hour"}},
        # With finished reads' reading time, which only article_read carries.
        # Optional, so the events still sync while read_seconds isn't
        # registered, only without the time.
        {model: EventStat, dimensions: {page_path: "pagePath", event_name: "eventName"}, metrics: EVENT_METRICS,
          optional_metrics: {read_seconds: "customEvent:read_seconds"}},
        # Every other event has no link, so they'd fill one "(not set)" row.
        {model: OutboundLinkStat, dimensions: {page_path: "pagePath", link_url: "linkUrl"}, metrics: EVENT_METRICS,
          filters: [["eventName", "EXACT", "click"]]},
        # Labels and methods in one report, of only the events that carry
        # either, or every page view and scroll would fill a "(not set)"
        # row; the click tracking sends an empty label when an element has
        # none. GA refuses this report until event_label and method are
        # registered as custom dimensions.
        {model: EventLabelStat, dimensions: {page_path: "pagePath", event_name: "eventName", event_label: "customEvent:event_label",
          event_method: "customEvent:method"},
          metrics: EVENT_METRICS, filters: [{any: [EventLabelStat::LABELLED, EventLabelStat::WITH_METHOD]}]},
        # GA refuses these two until metric_rating, content_category and
        # content_tags are registered. Each is narrowed to the events that
        # carry its parameters, or every other event would fill a "(not set)" row.
        {model: WebVitalStat, dimensions: {page_path: "pagePath", metric: "eventName", rating: "customEvent:metric_rating"},
          metrics: {event_count: "eventCount", value_sum: "eventValue"},
          filters: [["eventName", "FULL_REGEXP", WebVitalStat::METRICS.join("|")]]},
        {model: ContentGroupStat, dimensions: {page_path: "pagePath", content_group: "contentGroup",
          content_category: "customEvent:content_category", content_tags: "customEvent:content_tags"},
          metrics: {views: "screenPageViews"}, filters: [["eventName", "EXACT", "page_view"]]},
        # Not per page, since the search panel opens over any page and the
        # term is what's worth knowing.
        {
          model: SearchTermStat,
          dimensions: {search_term: "searchTerm", event_name: "eventName"},
          metrics: EVENT_METRICS,
          filters: [["eventName", "FULL_REGEXP", SearchTermStat::EVENTS.join("|")]]
        }
      ].freeze
      # GA leaves a dimension empty or "(not set)" when it couldn't tell; one
      # spelling keeps such rows together, and satisfies the key's presence.
      NOT_SET = "(not set)"
      UNKNOWN_COUNTRY = "ZZ"

      class << self
        def call(...)
          new(...).call
        end

        # So a row asked of GA live matches the row stored for it.
        def normalize(field, value)
          value = value.presence || NOT_SET
          return value unless field == :country

          # Search Console stats mark an unknown country the same way.
          value == NOT_SET ? UNKNOWN_COUNTRY : value.upcase
        end

        def dimensions_for(model)
          REPORTS.find { |report| report[:model] == model }&.fetch(:dimensions)
        end

        # So figures asked of GA live cover the same rows as the stored ones.
        def filters_for(model)
          REPORTS.find { |report| report[:model] == model }&.fetch(:filters, []) || []
        end

        # Some figures, like returning users, only exist under a filter of their
        # own, so they're asked apart from the rest.
        def extras_for(model)
          REPORTS.find { |report| report[:model] == model }&.fetch(:extra, []) || []
        end

        # A filter is [dimension, match type, value, exclude?], or {any: [...]}
        # holding lists of them, any one list of which may match.
        def dimension_filter(filters, hostname = Blog.host)
          {andGroup: {expressions: [hostname_filter(hostname)] + filters.map { |filter| filter_expression(filter) }}}
        end

        def hostname_filter(hostname = Blog.host)
          {filter: {fieldName: "hostName", stringFilter: {matchType: "EXACT", value: hostname}}}
        end

        private

        def filter_expression(filter)
          if filter.is_a?(Hash)
            return {orGroup: {expressions: filter.fetch(:any).map { |all| {andGroup: {expressions: all.map { |one| filter_expression(one) }}} }}}
          end

          dimension, match_type, value, exclude = filter
          expression = {filter: {fieldName: dimension, stringFilter: {matchType: match_type, value: value, caseSensitive: false}}}
          exclude ? {notExpression: expression} : expression
        end
      end

      # The numeric property ID (Admin > Property details), since the Data
      # API refuses the "G-" measurement ID.
      def initialize(options = {})
        connect(options, scope: SCOPE, cache: false)
        @end_date = options.fetch(:today) { Date.current }
        @start_date = @end_date - (options.fetch(:days, DEFAULT_DAYS).to_i.clamp(1..) - 1)
        # So a backfill of one report doesn't ask GA for every other one too.
        @reports = options[:only] ? REPORTS.select { |report| Array(options[:only]).include?(report[:model]) } : REPORTS
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No Analytics property configured (credentials google.analytics_property_id)" } if @property.blank?

        synced = SyncLock.hold("google/analytics") do
          @reports.each do |report|
            report[:model].sync(report_or_without_optional(report, result), result)
          # One refused report shouldn't cost the others.
          rescue ApiClient::Error => e
            result.errors << "Analytics: #{e.message}"
          end
          sync_cohorts(result) unless partial?
        end
        result.errors << "Analytics: another sync is already running, so this one was skipped" unless synced
        # A setup problem fails every report alike; one line says it.
        result.errors.uniq!
        result
      end

      private

      def partial?
        !@reports.equal?(REPORTS)
      end

      # Every finished week of the longest span the grid offers, whatever
      # days were asked for, since a cohort's later weeks keep filling in
      # long after it began.
      def sync_cohorts(result)
        CohortWeekStat.sync(CohortService.new(property: @property, client: @client, hostname: @hostname).finished_weeks(today: @end_date), result)
      rescue ApiClient::Error => e
        result.errors << "Analytics: #{e.message}"
      end

      # A refused optional figure, most likely one not registered yet, is
      # said, and the report asked again without it rather than lost.
      def report_or_without_optional(report, result)
        optional = report.fetch(:optional_metrics, {})
        return rows(report) if optional.empty?

        begin
          rows(report.merge(metrics: report.fetch(:metrics, TRAFFIC_METRICS).merge(optional)))
        rescue ApiClient::Error => e
          # Said only once the report comes back without it; refused again,
          # the report's own error says why.
          rows(report).tap do
            result.errors << "Analytics: #{e.message} (#{report[:model].model_name.human} synced without #{optional.keys.to_sentence})"
          end
        end
      end

      # An extra figure is merged into the row it belongs to, so a row is
      # saved once, and one GA has none of reads as zero rather than as what
      # an earlier sync stored.
      def rows(report)
        filters = report.fetch(:filters, [])
        rows = report_rows(report[:dimensions], report[:metrics] || TRAFFIC_METRICS, filters)
        report.fetch(:extra, []).each do |extra|
          keys = [:date, *report[:dimensions].keys]
          found = report_rows(report[:dimensions], extra[:metrics], filters + extra[:filters]).index_by { |row| row.values_at(*keys) }
          zero = extra[:metrics].keys.index_with(0)
          rows = rows.map { |row| row.merge(found.fetch(row.values_at(*keys), zero).slice(*zero.keys)) }
        end
        rows
      end

      def report_rows(dimension_names, metrics, filters)
        fetch_all(dimension_names.values, metrics.values, filters).map do |row|
          date, *values = row["dimensionValues"].map { |value| value["value"] }
          dimensions = dimension_names.keys.zip(values).to_h { |field, value| [field, self.class.normalize(field, value)] }
          counts = metrics.keys.zip(row["metricValues"].map { |value| value["value"] }).to_h do |field, value|
            [field, FLOAT_METRICS.include?(field) ? value.to_f : value.to_i]
          end
          {date: Date.strptime(date, "%Y%m%d"), **dimensions, **counts}
        end
      end

      def fetch_all(dimensions, metrics, filters)
        url = format(REPORT_URL, property: ERB::Util.url_encode(@property))
        rows = []
        loop do
          report = @client.post(url, {
            dateRanges: [{startDate: @start_date.iso8601, endDate: @end_date.iso8601}],
            dimensions: ["date", *dimensions].map { |name| {name: name} },
            metrics: metrics.map { |name| {name: name} },
            dimensionFilter: self.class.dimension_filter(filters, @hostname),
            limit: ROW_LIMIT, offset: rows.size,
            returnPropertyQuota: true
          })
          Quota.record("core", report)
          rows.concat(report.fetch("rows", []))
          return rows if rows.size >= report["rowCount"].to_i || report.fetch("rows", []).empty?
        end
      end
    end
  end
end
