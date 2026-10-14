# encoding: UTF-8

namespace :feed_entries do
  desc "Import a feed-entries CSV (#,URL,Title,Description,Type,Published,Updated,Tags,Categories): bin/rails 'feed_entries:import[path/to/file.csv]'"
  task :import, [:path] => :environment do |_task, args|
    abort "Usage: bin/rails 'feed_entries:import[path/to/file.csv]'" if args[:path].blank?

    result = FeedEntry.import_csv(File.read(args[:path], encoding: "bom|utf-8"))
    puts result.summary
    result.errors.each { |error| warn "  #{error}" }
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
