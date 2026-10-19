# encoding: UTF-8

module Google
  module PageSpeed
    # In the background, since a batch of PageSpeed runs takes minutes.
    class SyncJob < ApplicationJob
      queue_as :default

      def perform(limit: SyncService::DEFAULT_LIMIT, request_id: nil)
        result = SyncRequest.track("page_speed", request_id: request_id, limit: limit) do
          SyncService.call(limit: limit)
        end
        Rails.logger.info("PageSpeed sync: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("PageSpeed sync: #{error}") }
      end
    end
  end
end
