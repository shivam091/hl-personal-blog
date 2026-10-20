# encoding: UTF-8

module Google
  module SafeBrowsing
    # In the background, so nothing waits on Google's API.
    class SyncJob < ApplicationJob
      queue_as :default

      def perform(request_id: nil)
        result = SyncRequest.track("safe_browsing", request_id: request_id) { SyncService.call }
        Rails.logger.info("Safe Browsing sync: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("Safe Browsing sync: #{error}") }
      end
    end
  end
end
