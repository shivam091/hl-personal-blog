# encoding: UTF-8

module Google
  module SearchConsole
    # In the background, so nothing waits on Google's API. Parts can be
    # synced alone, so refreshing sitemaps doesn't spend the day's URL
    # inspection quota.
    class SyncJob < ApplicationJob
      PARTS = %w[performance sitemaps url_inspections].freeze

      queue_as :default

      # Not always today, so a range in the past can be backfilled.
      # A request stands for one part, so a run of several records each
      # part as its own.
      def perform(days = SyncService::DEFAULT_DAYS, ending = nil, only: PARTS,
        limit: UrlInspectionSyncService::DEFAULT_LIMIT, request_id: nil)
        today = ending ? Date.iso8601(ending) : Date.current
        {
          "performance" => [
            "Search Console sync",
            "search_console_performance",
            SyncRequest.range(days, today),
            -> { SyncService.call(days: days, today: today) }
          ],
          "sitemaps" => ["Search Console sitemaps sync", "search_console_sitemaps", {}, -> { SitemapSyncService.call }],
          "url_inspections" => ["URL inspection sync", "url_inspections", {limit: limit}, -> { UrlInspectionSyncService.call(limit: limit) }]
        }.slice(*only).each_value do |label, kind, attributes, sync|
          result = SyncRequest.track(kind, request_id: (request_id if only.one?), **attributes, &sync)
          Rails.logger.info("#{label}: #{result.summary}")
          result.errors.each { |error| Rails.logger.warn("#{label}: #{error}") }
        end
      end
    end
  end
end
