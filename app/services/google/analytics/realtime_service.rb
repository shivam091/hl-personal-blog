# encoding: UTF-8

module Google
  module Analytics
    # Read live rather than stored: GA's realtime report is stale within
    # minutes, and the daily reports count the same visits once GA has
    # processed them.
    class RealtimeService
      REPORT_URL = "https://analyticsdata.googleapis.com/v1beta/properties/%{property}:runRealtimeReport"
      # Realtime reports name pages by title; they have no page path. Pages and
      # events by count rather than users, as GA's own Realtime cards show them.
      BREAKDOWNS = {
        pages: ["unifiedScreenName", "screenPageViews"], events: ["eventName", "eventCount"],
        key_events: ["eventName", "keyEvents"], countries: ["countryId", "activeUsers"], cities: ["city", "activeUsers"],
        devices: ["deviceCategory", "activeUsers"], platforms: ["platform", "activeUsers"], per_minute: ["minutesAgo", "activeUsers"]
      }.freeze
      # GA's realtime window, which minutesAgo counts back over.
      MINUTES = 30
      # Short-lived, so a dashboard reloaded in a loop doesn't spend GA quota.
      CACHE_TTL = 1.minute

      Snapshot = Struct.new(:active_users, :pages, :events, :key_events, :countries, :cities, :devices, :platforms, :per_minute, :errors)
      # One event's, as GA's event page shows it beside the period's figures.
      # By country, since GA won't narrow a page title breakdown to an event.
      EventSnapshot = Struct.new(:event_count, :countries, :errors)

      class << self
        def call(...)
          new(...).call
        end

        def event(name, **)
          new(**).event(name)
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
      end

      def call
        snapshot = Snapshot.new(0, *Array.new(8) { {} }, [])
        return snapshot.tap { snapshot.errors << unconfigured } if unconfigured

        @cache.fetch("google/analytics_realtime/#{@property}", expires_in: CACHE_TTL) do
          # Asked for separately, since one visitor counts in every page row
          # they viewed and breakdown rows can't be added up to it.
          snapshot.active_users = counts_by(nil, metric: "activeUsers").values.sum
          BREAKDOWNS.each { |name, (dimension, metric)| snapshot[name] = counts_by(dimension, metric: metric) }
          # By the minute's time, oldest first and with quiet minutes as zero,
          # so it reads as a timeline.
          now = Time.current.beginning_of_minute
          snapshot.per_minute = (MINUTES - 1).downto(0).to_h { |ago| [now - ago.minutes, snapshot.per_minute.fetch(format("%02d", ago), 0)] }
          # GA lists every event with zero key events; only the key ones matter.
          snapshot.key_events = snapshot.key_events.select { |_name, count| count.positive? }
          snapshot
        end
      rescue ApiClient::Error => e
        snapshot.errors << "Analytics realtime: #{e.message}"
        snapshot
      end

      def event(name)
        snapshot = EventSnapshot.new(0, {}, [])
        return snapshot.tap { snapshot.errors << unconfigured } if unconfigured

        @cache.fetch("google/analytics_realtime/#{@property}/event/#{name}", expires_in: CACHE_TTL) do
          filter = {filter: {fieldName: "eventName", stringFilter: {matchType: "EXACT", value: name}}}
          snapshot.event_count = counts_by(nil, metric: "eventCount", filter: filter).values.sum
          snapshot.countries = counts_by(BREAKDOWNS[:countries].first, metric: "eventCount", filter: filter)
          snapshot
        end
      rescue ApiClient::Error => e
        snapshot.errors << "Analytics realtime: #{e.message}"
        snapshot
      end

      private

      def unconfigured
        if !@client.configured?
          ApiClient::NOT_CONFIGURED
        elsif @property.blank?
          "No Analytics property configured (credentials google.analytics_property_id)"
        end
      end

      def counts_by(dimension, metric:, filter: nil)
        report = @client.post(format(REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dimensions: [dimension].compact.map { |name| {name: name} }, metrics: [{name: metric}], dimensionFilter: filter,
          returnPropertyQuota: true
        }.compact)
        Quota.record("realtime", report)
        report.fetch("rows", [])
          .to_h { |row| [row.dig("dimensionValues", 0, "value"), row.dig("metricValues", 0, "value").to_i] }
          .sort_by { |_name, count| -count }.to_h
      end
    end
  end
end
