# encoding: UTF-8

namespace :crawled_pages do
  desc "Import a crawled-pages CSV (#,URL,Last modified,Status): bin/rails 'crawled_pages:import[path/to/file.csv]'"
  task :import, [:path] => :environment do |_task, args|
    abort "Usage: bin/rails 'crawled_pages:import[path/to/file.csv]'" if args[:path].blank?

    result = CrawledPage.import_csv(File.read(args[:path], encoding: "bom|utf-8"))
    puts result.summary
    result.errors.each { |error| warn "  #{error}" }
  end

  # Synchronous on purpose: the task's process exits when it's done, which
  # would drop a job queued in memory.
  desc "Create and update crawled pages from the blog's sitemap (credentials sitemap.url)"
  task sync_sitemap: :environment do
    result = SyncRequest.track("sitemap", trigger: "rake") { SitemapSyncService.call }
    puts "Sitemap sync: #{result.summary}"
    result.errors.each { |error| warn "  #{error}" }
    # A non-zero exit lets whatever ran the task tell it failed.
    exit 1 if result.failed?
  end

  desc "Export all crawled pages as CSV to a file, or to stdout: bin/rails 'crawled_pages:export[path/to/file.csv]'"
  task :export, [:path] => :environment do |_task, args|
    csv = CrawledPage.to_csv
    args[:path].present? ? File.write(args[:path], csv) : $stdout.write(csv)
    # Recorded under the page's own export URL, so it can be taken again
    # from the admin.
    ExportRequest.record(csv, path: Rails.application.routes.url_helpers.crawled_pages_path(format: :csv),
      filename: args[:path].present? ? File.basename(args[:path]) : "(stdout)", trigger: "rake")
  end
end
