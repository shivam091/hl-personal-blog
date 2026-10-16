# encoding: UTF-8

require "rails_helper"

RSpec.describe IndexCoverage do
  let(:today) { Date.new(2026, 10, 12) }

  before do
    CrawledPage.create!(url: "https://blog.example.com/", last_modified_at: Time.zone.parse("2026-10-01"), indexed: true)
    CrawledPage.create!(url: "https://blog.example.com/post/a", last_modified_at: Time.zone.parse("2026-01-01"))
    newer = CrawledPage.create!(url: "https://blog.example.com/post/b", last_modified_at: Time.zone.parse("2026-09-01"))
    Google::SearchConsole::UrlInspection.create!(crawled_page: newer, verdict: "NEUTRAL")
  end

  subject(:coverage) { described_class.new(today: today) }

  it "counts indexed pages and Search Console's verdicts" do
    expect([coverage.indexed, coverage.total]).to eq([1, 3])
    expect(coverage.verdicts).to eq("NEUTRAL" => 1)
  end

  it "lists pages missing from the index, most recently changed first" do
    expect(coverage.not_indexed.map(&:url)).to eq(%w[https://blog.example.com/post/b https://blog.example.com/post/a])
  end

  it "buckets pages by days since they changed" do
    expect(coverage.ages).to eq("Under 30 days" => 1, "30–90 days" => 1, "90–180 days" => 0, "180–365 days" => 1, "Over a year" => 0)
  end

  it "joins on paths" do
    expect(coverage.indexed_paths).to eq(Set["/"])
    expect(coverage.crawled_paths).to eq(Set["/", "/post/a", "/post/b"])
  end

  it "times the wait for indexing from the request when there is one, else from the last change" do
    CrawledPage.find_by(url: "https://blog.example.com/post/b").update!(index_requested_at: Time.zone.parse("2026-10-08"))

    expect(coverage.waiting.map { |row| [row.page.url, row.days, row.requested] }).to eq([
      ["https://blog.example.com/post/a", 284, false], ["https://blog.example.com/post/b", 4, true]
    ])
    expect(coverage.waiting_ages).to eq("Under a week" => 1, "1–4 weeks" => 0, "1–3 months" => 0, "Over 3 months" => 1)
  end

  it "buckets inspected pages by their last crawl and finds those changed since" do
    a = CrawledPage.find_by(url: "https://blog.example.com/post/a")
    Google::SearchConsole::UrlInspection.create!(crawled_page: a, last_crawled_at: Time.zone.parse("2025-12-01"))
    Google::SearchConsole::UrlInspection.find_by(crawled_page: CrawledPage.find_by(url: "https://blog.example.com/post/b"))
      .update!(last_crawled_at: Time.zone.parse("2026-10-10"))

    expect(coverage.crawl_ages).to eq("Under a week" => 1, "1–4 weeks" => 0, "1–3 months" => 0, "Over 3 months" => 1, "Never crawled" => 0)
    expect(coverage.changed_since_crawl.map { |row| [row.page.url, row.crawled_at.to_date] }).to eq([
      ["https://blog.example.com/post/a", Date.new(2025, 12, 1)]
    ])
  end

  it "finds entries the sitemap lacks and entry pages the feed no longer has" do
    %w[/post/b/ /tutorial/c].each do |path|
      FeedEntry.create!(url: "https://blog.example.com#{path}", name: path, type: "post",
        published_at: Time.zone.parse("2026-10-01"), last_modified_at: Time.zone.parse("2026-10-01"))
    end
    CrawledPage.create!(url: "https://blog.example.com/tag/css", last_modified_at: Time.zone.parse("2026-10-01"))

    expect(coverage.entries_missing_from_sitemap.map(&:url)).to eq(["https://blog.example.com/tutorial/c"])
    expect(coverage.sitemap_entries_missing_from_feed.map(&:url)).to eq(["https://blog.example.com/post/a"])
  end
end
