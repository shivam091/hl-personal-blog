# encoding: UTF-8

class SyncFeedJob < ApplicationJob
  queue_as :default

  def perform(request_id: nil)
    result = SyncRequest.track("feed", request_id: request_id) { FeedSyncService.call }
    Rails.logger.info("Feed sync: #{result.summary}")
    result.errors.each { |error| Rails.logger.warn("Feed sync: #{error}") }
  end
end
