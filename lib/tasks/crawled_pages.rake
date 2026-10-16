# encoding: UTF-8

namespace :crawled_pages do
  # Synchronous on purpose: the task's process exits when it's done, which
  # would drop a job queued in memory.
  desc "Create and update crawled pages from the blog's sitemap (credentials blog.url)"
  task sync_sitemap: :environment do
    result = SyncRequest.track("sitemap", trigger: "rake") { SitemapSyncService.call }
    puts "Sitemap sync: #{result.summary}"
    result.errors.each { |error| warn "  #{error}" }
    exit 1 if result.failed?
  end
end
