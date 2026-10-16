# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::SitemapSyncService do
  let(:url) { "https://searchconsole.googleapis.com/webmasters/v3/sites/https%3A%2F%2Fblog.example.com%2F/sitemaps" }
  let(:entry) do
    {
      path: "https://blog.example.com/sitemap.xml", type: "sitemap", isPending: false, isSitemapsIndex: false,
      lastSubmitted: "2026-10-01T10:00:00.123456Z", lastDownloaded: "2026-10-10T08:30:00Z",
      errors: "1", warnings: "2", contents: [{type: "web", submitted: "42", indexed: "0"}]
    }
  end

  def sync
    described_class.call(site: "https://blog.example.com/", client: google_client)
  end

  it "stores how Search Console last processed each sitemap" do
    google_stubs.get(url) { [200, {}, {sitemap: [entry]}.to_json] }

    expect(sync.summary).to eq("1 created, 0 updated, 0 unchanged, 0 failed")
    expect(Google::SearchConsole::Sitemap.all.sole).to have_attributes(
      path: "https://blog.example.com/sitemap.xml", sitemap_type: "sitemap", pending: false, sitemaps_index: false,
      last_submitted_at: Time.utc(2026, 10, 1, 10, 0, 0.123r), last_downloaded_at: Time.utc(2026, 10, 10, 8, 30),
      error_count: 1, warning_count: 2, contents: [{"type" => "web", "submitted" => 42}], submitted_urls: 42
    )
  end

  it "leaves an unchanged sitemap alone and keeps one no longer listed" do
    google_stubs.get(url) { [200, {}, {sitemap: [entry]}.to_json] }
    sync
    Google::SearchConsole::Sitemap.create!(path: "https://blog.example.com/old.xml")

    expect(sync.summary).to eq("0 created, 0 updated, 1 unchanged, 0 failed")
    expect(Google::SearchConsole::Sitemap.count).to eq(2)
  end

  it "keeps every sync's figures, counting the sitemap's pages inspected as indexed" do
    page = CrawledPage.create!(url: "https://blog.example.com/post", last_modified_at: Time.utc(2026, 10, 1))
    google_stubs.get(url) { [200, {}, {sitemap: [entry]}.to_json] }
    sync
    Google::SearchConsole::UrlInspection.create!(crawled_page: page, verdict: "PASS", sitemaps: [entry[:path]])
    sync

    expect(Google::SearchConsole::SitemapHistory.order(synced_at: :asc).map { |row| [row.submitted, row.indexed, row.error_count, row.warning_count] })
      .to eq([[42, nil, 1, 2], [42, 1, 1, 2]])
  end

  it "handles a property with no sitemaps" do
    google_stubs.get(url) { [200, {}, "{}"] }

    expect(sync.summary).to eq("0 created, 0 updated, 0 unchanged, 0 failed")
  end

  it "reports an API error instead of raising" do
    google_stubs.get(url) { [403, {}, {error: {message: "User does not have sufficient permission for site"}}.to_json] }

    expect(sync.errors).to eq(["Search Console sitemaps: User does not have sufficient permission for site"])
  end

  it "reports missing configuration" do
    expect(described_class.call(site: nil, client: google_client).errors.first).to include("google.search_console_site")
  end
end
