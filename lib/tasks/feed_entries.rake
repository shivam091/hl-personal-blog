# encoding: UTF-8

namespace :feed_entries do
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
