# encoding: UTF-8

module Google
  module Analytics
    # GA drops an event parameter from reports until it's registered as a
    # custom dimension or metric, so the blog's own parameters are registered
    # from here rather than left to be found missing.
    #
    # Setup: the service account must be an Editor of the property (Admin →
    # Property access management), since registering is a write and needs
    # the analytics.edit scope.
    class CustomDimensionService
      SCOPE = "https://www.googleapis.com/auth/analytics.edit"
      CREATE_URL = "#{SettingsService::ADMIN_URL}/customDimensions"
      CREATE_METRIC_URL = "#{SettingsService::ADMIN_URL}/customMetrics"

      class << self
        def call(...)
          new(...).call
        end

        def known?(parameter_name)
          SettingsService::EXPECTED_CUSTOM_DIMENSIONS.key?(parameter_name) || SettingsService::EXPECTED_CUSTOM_METRICS.key?(parameter_name)
        end
      end

      def initialize(parameter_name, options = {})
        @metric = SettingsService::EXPECTED_CUSTOM_METRICS[parameter_name]
        @dimension = @metric || SettingsService::EXPECTED_CUSTOM_DIMENSIONS.fetch(parameter_name)
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No Analytics property configured (credentials google.analytics_property_id)" } if @property.blank?

        body = {parameterName: @dimension.parameter_name, displayName: @dimension.display_name, scope: "EVENT"}
        body[:measurementUnit] = @metric.measurement_unit if metric?
        @client.post(format(metric? ? CREATE_METRIC_URL : CREATE_URL, property: ERB::Util.url_encode(@property)), body)
        result.created += 1
        # So the Settings page shows it registered rather than an hour-old list.
        @cache.delete(SettingsService.cache_key(@property))
        result
      rescue ApiClient::Error => e
        result.errors << "Custom #{metric? ? "metric" : "dimension"} #{@dimension.parameter_name}: #{e.message}"
        result
      end

      private

      def metric?
        !@metric.nil?
      end
    end
  end
end
