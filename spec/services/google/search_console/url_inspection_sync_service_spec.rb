# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::UrlInspectionSyncService do
  let(:site) { "https://blog.example.com/" }
  let(:inspected) { [] }

  def page(path, **attributes)
    CrawledPage.create!(url: "https://blog.example.com#{path}", last_modified_at: Time.utc(2026, 10, 1), **attributes)
  end

  def stub_inspections(verdicts: ["PASS"], &block)
    google_stubs.post(described_class::INSPECT_URL) do |env|
      body = JSON.parse(env.body)
      inspected << body["inspectionUrl"]
      next block.call(body) if block

      verdict = verdicts.size > 1 ? verdicts.shift : verdicts.first
      [200, {}, {inspectionResult: {
        inspectionResultLink: "https://search.google.com/search-console/inspect?resource_id=x",
        indexStatusResult: {
          verdict: verdict, coverageState: "Submitted and indexed", robotsTxtState: "ALLOWED", indexingState: "INDEXING_ALLOWED",
          pageFetchState: "SUCCESSFUL", crawledAs: "MOBILE", lastCrawlTime: "2026-10-09T05:06:07Z",
          googleCanonical: "https://blog.example.com/other", userCanonical: body["inspectionUrl"],
          sitemap: ["https://blog.example.com/sitemap.xml"], referringUrls: ["https://blog.example.com/"]
        },
        richResultsResult: {verdict: "PASS", detectedItems: [{richResultType: "Breadcrumbs", items: [{name: "Unnamed item", issues: [{issueMessage: "Missing field", severity: "WARNING"}]}]}]}
      }}.to_json]
    end
  end

  def sync(**options)
    described_class.call(site: site, client: google_client, **options)
  end

  it "stores Google's verdict on each page and marks the page indexed to match" do
    crawled = page("/post")
    stub_inspections

    expect(sync.summary).to eq("1 created, 0 updated, 0 unchanged, 0 failed")
    expect(crawled.reload.indexed).to be_truthy
    expect(crawled.url_inspection).to have_attributes(
      verdict: "PASS", coverage_state: "Submitted and indexed", robots_txt_state: "ALLOWED", indexing_state: "INDEXING_ALLOWED",
      page_fetch_state: "SUCCESSFUL", crawled_as: "MOBILE", last_crawled_at: Time.utc(2026, 10, 9, 5, 6, 7),
      sitemaps: ["https://blog.example.com/sitemap.xml"], referring_urls: ["https://blog.example.com/"], rich_results_verdict: "PASS",
      rich_results: [{"type" => "Breadcrumbs", "items" => [{"name" => "Unnamed item", "issues" => [{"message" => "Missing field", "severity" => "WARNING"}]}]}],
      inspection_link: "https://search.google.com/search-console/inspect?resource_id=x", indexed?: true, canonical_mismatch?: true
    )
  end

  def entry(path, published:)
    FeedEntry.create!(
      url: "https://blog.example.com#{path}",
      name: path,
      type: "tutorial",
      published_at: published,
      last_modified_at: published
    )
  end

  describe "new entries" do
    before do
      entry("/tutorial/new", published: 1.day.ago)
      entry("/tutorial/rechecked", published: 10.days.ago)
      entry("/tutorial/recent", published: 5.days.ago)
      entry("/tutorial/indexed", published: 2.days.ago)
      entry("/tutorial/old", published: 60.days.ago)
      entry("/tutorial/unlisted", published: 1.day.ago)
      page("/tutorial/new")

      Google::SearchConsole::UrlInspection.create!(
        crawled_page: page("/tutorial/rechecked"),
        verdict: "NEUTRAL",
        inspected_at: 4.days.ago
      )

      Google::SearchConsole::UrlInspection.create!(
        crawled_page: page("/tutorial/recent"),
        verdict: "NEUTRAL",
        inspected_at: 1.day.ago
      )

      page("/tutorial/indexed", indexed: true)
      page("/tutorial/old")
    end

    it "inspects ones never inspected, and ones still not indexed a few days on" do
      stub_inspections

      described_class.new(site: site, client: google_client).inspect_new_entries

      expect(inspected).to contain_exactly(
        "https://blog.example.com/tutorial/new",
        "https://blog.example.com/tutorial/rechecked"
      )
    end

    it "puts unindexed new entries first in the daily batch" do
      page("/a")
      stub_inspections

      sync(limit: 3)

      expect(inspected.first(3)).to contain_exactly(
        "https://blog.example.com/tutorial/new",
        "https://blog.example.com/tutorial/rechecked",
        "https://blog.example.com/tutorial/recent"
      )
    end
  end

  it "inspects pages waiting on an indexing request first, and closes the request once Google has the page" do
    page("/a")
    requested = page("/z", index_requested_at: 1.day.ago)
    stub_inspections

    sync(limit: 1)

    expect(inspected).to eq(["https://blog.example.com/z"])
    expect(requested.reload).to have_attributes(indexed: true, index_requested_at: nil)
  end

  it "inspects one page now, whatever its turn in the batches" do
    page("/old")
    crawled = page("/new")
    stub_inspections

    result = described_class.new(site: site, client: google_client).inspect_now(crawled)

    expect(result.summary).to eq("1 created, 0 updated, 0 unchanged, 0 failed")
    expect(inspected).to eq(["https://blog.example.com/new"])
    expect(crawled.reload.indexed).to be_truthy
  end

  it "keeps the first crawl seen, never moving it for a recrawl or setting it on a page already crawled" do
    fresh = page("/fresh")
    Google::SearchConsole::UrlInspection.create!(crawled_page: fresh, verdict: "NEUTRAL", inspected_at: 2.days.ago)
    known = page("/known")
    Google::SearchConsole::UrlInspection.create!(crawled_page: known, verdict: "PASS", inspected_at: 2.days.ago,
      last_crawled_at: Time.utc(2026, 9, 1))
    crawl_times = {fresh.url => ["2026-10-09T05:06:07Z", "2026-10-15T00:00:00Z"], known.url => ["2026-10-09T05:06:07Z"]}
    stub_inspections do |body|
      [200, {}, {inspectionResult: {indexStatusResult: {verdict: "PASS", lastCrawlTime: crawl_times.fetch(body["inspectionUrl"]).shift}}}.to_json]
    end

    sync
    described_class.new(site: site, client: google_client).inspect_now(fresh.reload)

    expect(fresh.reload.url_inspection).to have_attributes(first_crawled_at: Time.utc(2026, 10, 9, 5, 6, 7), last_crawled_at: Time.utc(2026, 10, 15))
    expect(known.reload.url_inspection.first_crawled_at).to be_nil
  end

  it "marks a page Google dropped as not indexed, updating its inspection" do
    crawled = page("/post", indexed: true)
    stub_inspections(verdicts: %w[PASS NEUTRAL])
    sync

    expect(sync.summary).to eq("0 created, 1 updated, 0 unchanged, 0 failed")
    expect(crawled.reload.indexed).to be_falsy
    expect(Google::SearchConsole::UrlInspection.count).to eq(1)
  end

  it "keeps a page's past verdicts, only those that changed, so a drop out of the index is dated" do
    crawled = page("/post", indexed: true)
    stub_inspections(verdicts: %w[PASS PASS NEUTRAL])
    3.times { sync }

    expect(Google::SearchConsole::UrlInspectionHistory.timeline(crawled).map { |change| [change.verdict, change.url] }).to eq([
      ["NEUTRAL", crawled.url], ["PASS", crawled.url]
    ])
  end

  it "inspects pages never inspected first, then those inspected longest ago, up to the limit" do
    recent, stale, fresh = page("/recent"), page("/stale"), page("/fresh")
    Google::SearchConsole::UrlInspection.create!(crawled_page: recent, inspected_at: 1.day.ago)
    Google::SearchConsole::UrlInspection.create!(crawled_page: stale, inspected_at: 10.days.ago)
    stub_inspections

    sync(limit: 2)

    expect(inspected).to eq([fresh.url, stale.url])
  end

  it "stops after a run of errors rather than spending the batch on them" do
    4.times { |n| page("/p#{n}") }
    stub_inspections { [429, {}, {error: {message: "Quota exceeded"}}.to_json] }

    result = sync
    expect(result.errors.size).to eq(described_class::MAX_CONSECUTIVE_ERRORS)
    expect(result.errors.first).to eq("URL inspection of https://blog.example.com/p0: Quota exceeded")
    expect(inspected.size).to eq(described_class::MAX_CONSECUTIVE_ERRORS)
  end

  it "reports missing configuration" do
    expect(described_class.call(site: nil, client: google_client).errors.first).to include("google.search_console_site")
  end
end
