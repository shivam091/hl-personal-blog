# encoding: UTF-8

module Google
  module Analytics
    # GA drops an event parameter from reports until it's registered as a
    # custom dimension, so the blog's own parameters are registered from here
    # rather than left to be found missing.
    #
    # Setup: the service account must be an Editor of the property (Admin →
    # Property access management), since registering is a write and needs
    # the analytics.edit scope.
    class CustomDimensionService
      SCOPE = "https://www.googleapis.com/auth/analytics.edit"
      CREATE_URL = "#{SettingsService::ADMIN_URL}/customDimensions"

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(parameter_name, options = {})
        @dimension = SettingsService::EXPECTED_CUSTOM_DIMENSIONS.fetch(parameter_name)
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No Analytics property configured (credentials google.analytics_property_id)" } if @property.blank?

        @client.post(format(CREATE_URL, property: ERB::Util.url_encode(@property)),
          {parameterName: @dimension.parameter_name, displayName: @dimension.display_name, scope: "EVENT"})
        result.created += 1
        # So the Settings page shows it registered rather than an hour-old list.
        @cache.delete(SettingsService.cache_key(@property))
        result
      rescue ApiClient::Error => e
        result.errors << "Custom dimension #{@dimension.parameter_name}: #{e.message}"
        result
      end
    end
  end
end
