# encoding: UTF-8

module Google
  module Analytics
    module Connected
      private

      def connect(options, scope: SyncService::SCOPE, cache: true, hostname: true)
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: scope) }
        @cache = options.fetch(:cache, Rails.cache) if cache
        @hostname = options.fetch(:hostname) { Blog.host } if hostname
      end
    end
  end
end
