# encoding: UTF-8

class SyncFeedJob < ApplicationJob
  queue_as :default

  def perform(request_id: nil)
    result = SyncRequest.track("feed", request_id: request_id) { FeedSyncService.call }
    Rails.logger.info("Feed sync: #{result.summary}")
    result.errors.each { |error| Rails.logger.warn("Feed sync: #{error}") }
    return unless result.created.positive?

    # A new entry is in the sitemap too, so Google is told it changed.
    Google::SearchConsole::SitemapSubmitJob.perform_later
    inspect_new_entries
  end

  private

  # So a new entry's verdict is known without waiting for the next day's batch.
  def inspect_new_entries
    result = SyncRequest.track("url_inspections") do
      Google::SearchConsole::UrlInspectionSyncService.new.inspect_new_entries
    end
    Rails.logger.info("New entry URL inspection: #{result.summary}")
  end
end
