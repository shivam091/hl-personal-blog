# encoding: UTF-8

namespace :feed_entries do
  # Synchronous on purpose: the task's process exits when it's done, which
  # would drop a job queued in memory.
  desc "Create and update feed entries, tags, and categories from the blog's Atom feed (credentials atom_feed.url, or env ATOM_FEED_URL)"
  task sync_feed: :environment do
    result = SyncRequest.track("feed", trigger: "rake") { FeedSyncService.call }
    puts "Feed sync: #{result.summary}"
    result.errors.each { |error| warn "  #{error}" }
    # A non-zero exit lets whatever ran the task tell it failed.
    exit 1 if result.failed?
  end

  desc "Export all feed entries as CSV to a file, or to stdout: bin/rails 'feed_entries:export[path/to/file.csv]'"
  task :export, [:path] => :environment do |_task, args|
    csv = FeedEntry.to_csv
    args[:path].present? ? File.write(args[:path], csv) : $stdout.write(csv)
    # Recorded under the page's own export URL, so it can be taken again
    # from the admin.
    ExportRequest.record(csv, path: Rails.application.routes.url_helpers.feed_entries_path(format: :csv),
      filename: args[:path].present? ? File.basename(args[:path]) : "(stdout)", trigger: "rake")
  end
end
