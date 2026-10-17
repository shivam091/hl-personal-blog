# encoding: UTF-8

module Google
  module Analytics
    class SyncJob < ApplicationJob
      queue_as :default

      # Not always today, so a range in the past can be backfilled.
      def perform(days = SyncService::DEFAULT_DAYS, ending = nil, request_id: nil)
        today = ending ? Date.iso8601(ending) : Date.current
        result = SyncRequest.track("analytics", request_id: request_id, **SyncRequest.range(days, today)) do
          SyncService.call(days: days, today: today)
        end
        Rails.logger.info("Analytics sync: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("Analytics sync: #{error}") }
      end
    end
  end
end
