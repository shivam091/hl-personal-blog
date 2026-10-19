# encoding: UTF-8

# Synchronous on purpose: the task's process exits when it's done, which
# would drop a job queued in memory.
report_sync = lambda do |label, result|
  puts "#{label}: #{result.summary}"
  result.errors.each { |error| warn "  #{error}" }
  exit 1 if result.failed?
end

namespace :google do
  namespace :search_console do
    desc "Create and update Search Console stats for the last N days (default: from the first day not yet final, credentials google.*): bin/rails 'google:search_console:sync[days]'"
    task :sync, [:days] => :environment do |_task, args|
      days = args[:days].presence || Google::SearchConsole::SyncService.unsettled_days
      report_sync.call("Search Console sync", SyncRequest.track("search_console_performance", trigger: "rake", **SyncRequest.range(days)) do
        Google::SearchConsole::SyncService.call(days: days)
      end)
    end

    desc "Copy how Search Console last processed each submitted sitemap (credentials google.*)"
    task sync_sitemaps: :environment do
      report_sync.call("Search Console sitemaps sync", SyncRequest.track("search_console_sitemaps", trigger: "rake") do
        Google::SearchConsole::SitemapSyncService.call
      end)
    end

    desc "Submit the blog's sitemap to Search Console, then copy how it was processed (credentials google.*, blog.url)"
    task submit_sitemap: :environment do
      report_sync.call("Sitemap submission", SyncRequest.track("sitemap_submission", trigger: "rake") do
        Google::SearchConsole::SitemapSubmitService.call
      end)
    end

    desc "Inspect up to N crawled pages with URL Inspection, least recently inspected first (default 100, credentials google.*): bin/rails 'google:search_console:inspect_urls[limit]'"
    task :inspect_urls, [:limit] => :environment do |_task, args|
      limit = (args[:limit].presence || Google::SearchConsole::UrlInspectionSyncService::DEFAULT_LIMIT).to_i
      report_sync.call("URL inspection sync", SyncRequest.track("url_inspections", trigger: "rake", limit: limit) do
        Google::SearchConsole::UrlInspectionSyncService.call(limit: limit)
      end)
    end

    desc "Inspect feed entries published in the last 30 days that Google hasn't indexed, if new or not inspected for 3 days (credentials google.*)"
    task inspect_new_entries: :environment do
      report_sync.call("New entry URL inspection", SyncRequest.track("url_inspections", trigger: "rake") do
        Google::SearchConsole::UrlInspectionSyncService.new.inspect_new_entries
      end)
    end
  end

  namespace :analytics do
    desc "Create and update Google Analytics stats for the last N days (default 7, credentials google.*): bin/rails 'google:analytics:sync[days]'"
    task :sync, [:days] => :environment do |_task, args|
      days = args[:days].presence || Google::Analytics::SyncService::DEFAULT_DAYS
      report_sync.call("Analytics sync", SyncRequest.track("analytics", trigger: "rake", **SyncRequest.range(days)) do
        Google::Analytics::SyncService.call(days: days)
      end)
    end

    # Once, after GA reports that repeated each other were merged: campaigns
    # into sources, first-user campaigns into user acquisition, landing
    # pages into landing page + source, page titles and new vs returning into
    # page traffic, content groups' daily rows into one per page, devices,
    # countries, places and referrers into one audience report, finished
    # reads into events, and event methods into event labels. Rows
    # stored before it are keyed without the new splits, so they'd be added
    # to the new ones. GA keeps its standard reports for good, so every day
    # since tracking began is fetched again. Safe to run again if it fails.
    desc "Drop the GA collections merged away, and refill the merged ones from the first tracked day (credentials google.*)"
    task rebuild_merged_reports: :environment do
      db = Mongoid.default_client
      %w[
        google_analytics_campaign_stats google_analytics_first_campaign_stats google_analytics_landing_page_stats
        google_analytics_page_title_stats google_analytics_visitor_type_stats google_analytics_device_stats
        google_analytics_country_stats google_analytics_location_stats google_analytics_referrer_stats
        google_analytics_article_read_stats google_analytics_event_method_stats
      ].each do |name|
        db[name].drop
        puts "Dropped #{name}"
      end
      models = [
        Google::Analytics::Stat, Google::Analytics::SourceStat, Google::Analytics::UserAcquisitionStat, Google::Analytics::ContentGroupStat,
        Google::Analytics::AudienceStat, Google::Analytics::EventStat, Google::Analytics::EventLabelStat
      ]
      models.each do |model|
        model.collection.drop
        model.create_indexes
        puts "Emptied #{model.collection.name} and created its indexes"
      end
      days = (Date.current - Google::Analytics::TrackedSince::ANALYTICS).to_i + 1
      report_sync.call("Analytics rebuild", SyncRequest.track("analytics", trigger: "rake", **SyncRequest.range(days)) do
        Google::Analytics::SyncService.call(days: days, only: models)
      end)
    end
  end

  namespace :page_speed do
    desc "Run PageSpeed Insights on up to N pages, least recently tested first (default 30, credentials google.api_key): bin/rails 'google:page_speed:sync[limit]'"
    task :sync, [:limit] => :environment do |_task, args|
      limit = (args[:limit].presence || Google::PageSpeed::SyncService::DEFAULT_LIMIT).to_i
      report_sync.call("PageSpeed sync", SyncRequest.track("page_speed", trigger: "rake", limit: limit) do
        Google::PageSpeed::SyncService.call(limit: limit)
      end)
    end
  end

  namespace :recaptcha do
    desc "Create and update daily reCAPTCHA score stats for every day Google still holds (credentials google.*, recaptcha.site_key)"
    task sync: :environment do
      report_sync.call("reCAPTCHA metrics sync", SyncRequest.track("recaptcha_metrics", trigger: "rake") do
        Google::Recaptcha::MetricsSyncService.call
      end)
    end
  end
end
