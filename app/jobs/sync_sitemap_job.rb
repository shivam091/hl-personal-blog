# encoding: UTF-8

# New posts can be pulled in as soon as they're published, without the
# admin waiting on fetching the sitemap and saving every page.
class SyncSitemapJob < ApplicationJob
  queue_as :default

  def perform(request_id: nil)
    result = SyncRequest.track("sitemap", request_id: request_id) { SitemapSyncService.call }
    Rails.logger.info("Sitemap sync: #{result.summary}")
    result.errors.each { |error| Rails.logger.warn("Sitemap sync: #{error}") }
  end
end
