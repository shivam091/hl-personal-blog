# encoding: UTF-8

module Google
  module SearchConsole
    # In the background, so nothing waits on Google's API.
    class SitemapSubmitJob < ApplicationJob
      queue_as :default

      def perform(request_id: nil)
        result = SyncRequest.track("sitemap_submission", request_id: request_id) do
          SitemapSubmitService.call
        end
        Rails.logger.info("Sitemap submission: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("Sitemap submission: #{error}") }
      end
    end
  end
end
