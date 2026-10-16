# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::CrawlDelays do
  def entry(path, published:, first_crawled: nil, inspected: published)
    url = "https://blog.example.com#{path}"
    FeedEntry.create!(url: url, name: path, type: "post", published_at: published, last_modified_at: published)
    page = CrawledPage.create!(url: url, last_modified_at: published)
    Google::SearchConsole::UrlInspection.create!(crawled_page: page, verdict: "PASS", first_crawled_at: first_crawled, created_at: inspected)
  end

  it "buckets the days from publishing to the first crawl of entries inspected while new" do
    published = Time.zone.local(2026, 10, 1, 9)
    entry("/same-day", published: published, first_crawled: published + 3.hours)
    entry("/two-days", published: published, first_crawled: published + 2.days)
    entry("/ten-days", published: published, first_crawled: published + 10.days)
    entry("/not-crawled", published: published)
    entry("/old", published: published - 1.year, first_crawled: published, inspected: published)
    entry("/republished", published: published, first_crawled: published - 1.day)

    delays = described_class.new

    expect(delays.days).to contain_exactly(0, 2, 10)
    expect(delays.counts).to include("0" => 1, "2–3" => 1, "8–14" => 1, "29+" => 0)
    expect(delays.median).to eq(2)
  end

  it "can count the days to first indexed instead" do
    published = Time.zone.local(2026, 10, 1, 9)
    entry("/slow", published: published, first_crawled: published + 1.day).update!(first_indexed_at: published + 5.days)
    entry("/unindexed", published: published, first_crawled: published + 1.day)

    expect(described_class.new(:first_indexed_at).days).to eq([5])
  end

  it "has no median without entries" do
    expect(described_class.new.median).to be_nil
  end
end
