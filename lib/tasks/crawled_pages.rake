# encoding: UTF-8

namespace :crawled_pages do
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
