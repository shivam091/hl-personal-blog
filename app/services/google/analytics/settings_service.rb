# encoding: UTF-8

module Google
  module Analytics
    # Exists because a setting left at its default (two months of event
    # data, a conversion not marked as a key event) quietly limits every
    # report built on it.
    class SettingsService
      include Connected

      ADMIN_URL = "https://analyticsadmin.googleapis.com/v1beta/properties/%{property}"
      # Enhanced measurement is only in the alpha API, which takes a stream's
      # full resource name.
      ALPHA_URL = "https://analyticsadmin.googleapis.com/v1alpha/%{name}/enhancedMeasurementSettings"
      # So are Google signals, which age and gender depend on.
      SIGNALS_URL = "https://analyticsadmin.googleapis.com/v1alpha/properties/%{property}/googleSignalsSettings"
      CACHE_FOR = 1.hour
      # The events that mean a reader acted rather than browsed. GA counts
      # one as a conversion only once it is marked so, and the first two are
      # sent from the blog's server.
      EXPECTED_KEY_EVENTS = %w[newsletter_subscribe contact_submit article_read like sandbox_download sandbox_open_external share].freeze
      # GA's names for how long event-level data is kept, read as a reader
      # would put them.
      RETENTION = {
        "TWO_MONTHS" => "2 months", "FOURTEEN_MONTHS" => "14 months", "TWENTY_SIX_MONTHS" => "26 months",
        "THIRTY_EIGHT_MONTHS" => "38 months", "FIFTY_MONTHS" => "50 months"
      }.freeze

      KeyEvent = Struct.new(:event_name, :counting_method, :custom, keyword_init: true)
      CustomDimension = Struct.new(:display_name, :parameter_name, :scope, keyword_init: true)
      CustomMetric = Struct.new(:display_name, :parameter_name, :scope, :measurement_unit, keyword_init: true)
      # The parameters the blog's tracking sends, which GA leaves out of
      # every report until each is registered.
      EXPECTED_CUSTOM_DIMENSIONS = {
        "event_label" => CustomDimension.new(display_name: "Event label", parameter_name: "event_label"),
        "metric_rating" => CustomDimension.new(display_name: "Web Vitals rating", parameter_name: "metric_rating"),
        "content_category" => CustomDimension.new(display_name: "Content category", parameter_name: "content_category"),
        "content_tags" => CustomDimension.new(display_name: "Content tags", parameter_name: "content_tags"),
        "link_domain" => CustomDimension.new(display_name: "Link domain", parameter_name: "link_domain"),
        "outbound" => CustomDimension.new(display_name: "Outbound", parameter_name: "outbound"),
        "method" => CustomDimension.new(display_name: "Method", parameter_name: "method")
      }.freeze
      # A number GA could only count as a dimension's distinct values unless
      # it's registered as a metric, which it then sums.
      EXPECTED_CUSTOM_METRICS = {
        "read_seconds" => CustomMetric.new(display_name: "Read seconds", parameter_name: "read_seconds", measurement_unit: "SECONDS")
      }.freeze
      # Events the reports here are built on that GA only sends with these
      # switched on, since the blog's own tracking doesn't send them.
      EXPECTED_ENHANCED_MEASUREMENT = {
        scrolls: "scroll events (Engagement)",
        outbound_clicks: "outbound link clicks (Engagement's Outbound links, and Link safety)"
      }.freeze
      # Events the blog already sends itself, so GA sending them too counts
      # each one twice.
      UNWANTED_ENHANCED_MEASUREMENT = {
        page_changes: "a page view on browser history changes, which the blog already sends itself, so back and forward count twice"
      }.freeze
      EnhancedMeasurement = Struct.new(
        :stream_enabled, :scrolls, :outbound_clicks, :site_search, :video_engagement, :file_downloads,
        :page_changes, :form_interactions, keyword_init: true
      ) do
        # GA ignores a toggle while the stream's master switch is off.
        def enabled?(event)
          stream_enabled && self[event]
        end
      end
      DataStream = Struct.new(:display_name, :url, :measurement_id, :enhanced_measurement, keyword_init: true) do
        # Unknown when GA wouldn't say, so a refused alpha call isn't read as
        # everything switched off.
        def missing_enhanced_measurement
          return [] unless enhanced_measurement

          EXPECTED_ENHANCED_MEASUREMENT.keys.reject { |event| enhanced_measurement.enabled?(event) }
        end

        # Empty when GA wouldn't say, for the same reason.
        def unwanted_enhanced_measurement
          return [] unless enhanced_measurement

          UNWANTED_ENHANCED_MEASUREMENT.keys.select { |event| enhanced_measurement.enabled?(event) }
        end
      end
      Settings = Struct.new(
        :display_name, :time_zone, :event_retention, :reset_on_new_activity, :key_events,
        :custom_dimensions, :custom_metrics, :data_streams, :annotations, :google_signals, keyword_init: true
      ) do
        def retention_label
          RETENTION.fetch(event_retention, event_retention.to_s.humanize.presence || "Unknown")
        end

        # Two months is GA's default, and it also caps how far back an
        # Exploration can look.
        def short_retention?
          event_retention == "TWO_MONTHS"
        end

        # Nil when GA wouldn't say, so a refused alpha call isn't read as off.
        def google_signals_off?
          !google_signals.nil? && google_signals != "GOOGLE_SIGNALS_ENABLED"
        end

        def missing_key_events
          EXPECTED_KEY_EVENTS - key_events.map(&:event_name)
        end

        # Only event-scoped ones count, since a user-scoped dimension of the
        # same parameter doesn't split events.
        def missing_custom_dimensions
          registered = custom_dimensions.select { |dimension| dimension.scope == "EVENT" }.map(&:parameter_name)
          EXPECTED_CUSTOM_DIMENSIONS.keys - registered
        end

        def missing_custom_metrics
          registered = custom_metrics.select { |metric| metric.scope == "EVENT" }.map(&:parameter_name)
          EXPECTED_CUSTOM_METRICS.keys - registered
        end
      end
      Result = Struct.new(:settings, :errors, keyword_init: true)

      class << self
        def call(...)
          new(...).call
        end

        # Versioned, so a Settings cached before a field was added isn't
        # read back.
        def cache_key(property)
          "google/analytics_settings/v5/#{property}"
        end
      end

      def initialize(options = {})
        connect(options, hostname: false)
      end

      def call
        return Result.new(settings: nil, errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        if @property.blank?
          return Result.new(
            settings: nil,
            errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
          )
        end

        settings = @cache.fetch(self.class.cache_key(@property), expires_in: CACHE_FOR) { fetch }
        Result.new(settings: settings, errors: [])
      rescue ApiClient::Error => e
        Result.new(settings: nil, errors: ["Analytics settings: #{e.message}"])
      end

      private

      def fetch
        base = format(ADMIN_URL, property: ERB::Util.url_encode(@property))
        property = @client.get(base)
        retention = @client.get("#{base}/dataRetentionSettings")
        Settings.new(
          display_name: property["displayName"],
          time_zone: property["timeZone"],
          event_retention: retention["eventDataRetention"],
          reset_on_new_activity: retention["resetUserDataOnNewActivity"],
          key_events: list("#{base}/keyEvents", "keyEvents").map do |event|
            KeyEvent.new(event_name: event["eventName"], counting_method: event["countingMethod"], custom: event["custom"])
          end.sort_by(&:event_name),
          custom_dimensions: list("#{base}/customDimensions", "customDimensions").map do |dimension|
            CustomDimension.new(
              display_name: dimension["displayName"],
              parameter_name: dimension["parameterName"],
              scope: dimension["scope"]
            )
          end.sort_by(&:display_name),
          custom_metrics: list("#{base}/customMetrics", "customMetrics").map do |metric|
            CustomMetric.new(
              display_name: metric["displayName"],
              parameter_name: metric["parameterName"],
              scope: metric["scope"],
              measurement_unit: metric["measurementUnit"]
            )
          end.sort_by(&:display_name),
          data_streams: data_streams(base),
          annotations: annotations,
          google_signals: google_signals
        )
      end

      def google_signals
        @client.get(format(SIGNALS_URL, property: ERB::Util.url_encode(@property)))["state"]
      rescue ApiClient::Error
        nil
      end

      # Newest first, as GA's own list has them. Nil rather than empty when
      # the alpha API refuses, so it isn't read as there being none.
      def annotations
        url = format(AnnotationService::LIST_URL, property: ERB::Util.url_encode(@property))
        AnnotationService.list(@client, url).sort_by { |annotation| annotation.date || Date.new(0) }.reverse
      rescue ApiClient::Error
        nil
      end

      # Web streams only, since the blog has no app.
      def data_streams(base)
        list("#{base}/dataStreams", "dataStreams").select { |stream| stream["type"] == "WEB_DATA_STREAM" }.map do |stream|
          web = stream.fetch("webStreamData", {})
          DataStream.new(
            display_name: stream["displayName"],
            url: web["defaultUri"],
            measurement_id: web["measurementId"],
            enhanced_measurement: enhanced_measurement(stream["name"])
          )
        end.sort_by { |stream| stream.display_name.to_s }
      end

      # An alpha endpoint may be refused or withdrawn, which shouldn't cost
      # the rest of the page.
      def enhanced_measurement(name)
        settings = @client.get(format(ALPHA_URL, name: name))
        EnhancedMeasurement.new(
          stream_enabled: settings["streamEnabled"],
          scrolls: settings["scrollsEnabled"],
          outbound_clicks: settings["outboundClicksEnabled"],
          site_search: settings["siteSearchEnabled"],
          video_engagement: settings["videoEngagementEnabled"],
          file_downloads: settings["fileDownloadsEnabled"],
          page_changes: settings["pageChangesEnabled"],
          form_interactions: settings["formInteractionsEnabled"]
        )
      rescue ApiClient::Error
        nil
      end

      # Paged, though a blog's property rarely has more than one page.
      def list(url, key)
        items = []
        token = nil
        loop do
          page = @client.get("#{url}?#{URI.encode_www_form({pageSize: 200, pageToken: token}.compact)}")
          items.concat(Array(page[key]))
          token = page["nextPageToken"].presence
          return items unless token
        end
      end
    end
  end
end
