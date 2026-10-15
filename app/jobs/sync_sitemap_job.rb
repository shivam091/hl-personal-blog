# encoding: UTF-8

class SyncSitemapJob < ApplicationJob
  queue_as :default

  def perform(request_id: nil)
    result = SyncRequest.track("sitemap", request_id: request_id) { SitemapSyncService.call }
    Rails.logger.info("Sitemap sync: #{result.summary}")
    result.errors.each { |error| Rails.logger.warn("Sitemap sync: #{error}") }
  end
end
