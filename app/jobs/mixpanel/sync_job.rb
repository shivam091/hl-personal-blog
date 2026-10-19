# encoding: UTF-8

module Mixpanel
  class SyncJob < ApplicationJob
    queue_as :default

    def perform(days = SyncService::DEFAULT_DAYS, to = Date.current.iso8601, request_id: nil)
      result = SyncRequest.track("mixpanel", request_id: request_id, **SyncRequest.range(days, Date.parse(to))) do
        SyncService.call(days: days, to: Date.parse(to))
      end
      Rails.logger.info("Mixpanel sync: #{result.summary}")
      result.errors.each { |error| Rails.logger.warn("Mixpanel sync: #{error}") }
    end
  end
end
