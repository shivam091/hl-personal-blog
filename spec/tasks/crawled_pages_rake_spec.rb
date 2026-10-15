# encoding: UTF-8

require "rails_helper"
require "rake"

RSpec.describe "crawled_pages rake tasks" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  it "records a sync as started by a rake task" do
    allow(SitemapSyncService).to receive(:call) { SyncResult.new(2, 0, 1, []) }

    expect { run("crawled_pages:sync_sitemap") }.to output(/Sitemap sync: 2 created/).to_stdout

    expect(SyncRequest.first).to have_attributes(kind: "sitemap", trigger: "rake", status: "succeeded", created_count: 2)
  end

  it "records an export to a file under the page's own export URL" do
    CrawledPage.create!(url: "https://example.com/a", last_modified_at: Time.utc(2026, 10, 1))
    path = Rails.root.join("tmp", "crawled-pages-spec.csv").to_s

    run("crawled_pages:export", path)

    expect(ExportRequest.first).to have_attributes(section: "Crawled pages", trigger: "rake", filename: "crawled-pages-spec.csv",
      path: "/crawled-pages.csv", row_count: 1)
  ensure
    FileUtils.rm_f(path) if path
  end
end
