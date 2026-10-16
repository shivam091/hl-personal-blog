# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::PageIndexing do
  let(:today) { Date.new(2026, 10, 10) }
  let(:sitemap) { "https://blog.example.com/sitemap.xml" }

  def page(path, verdict:, inspected_at:, sitemaps: [], coverage: nil, history: [])
    crawled = CrawledPage.create!(url: "https://blog.example.com#{path}", last_modified_at: Time.zone.local(2026, 9, 1))
    inspection = Google::SearchConsole::UrlInspection.create!(crawled_page: crawled, verdict: verdict, coverage_state: coverage,
      inspected_at: inspected_at, sitemaps: sitemaps)
    history.each do |at, state|
      Google::SearchConsole::UrlInspectionHistory.create!(crawled_page: crawled, url: crawled.url, inspected_at: at, verdict: state)
    end
    inspection
  end

  def indexing(params = {})
    described_class.new(params.merge(indexing_range: "28"), today: today)
  end

  before do
    page("/in", verdict: "PASS", inspected_at: Time.zone.local(2026, 10, 9), sitemaps: [sitemap],
      history: [[Time.zone.local(2026, 10, 5, 12), "NEUTRAL"], [Time.zone.local(2026, 10, 8, 9), "PASS"]])
    page("/out", verdict: "NEUTRAL", coverage: "Crawled - currently not indexed", inspected_at: Time.zone.local(2026, 10, 7, 12))
  end

  it "counts each day's pages as the last inspection by then found them, nil before any was inspected" do
    chart = indexing
    days = chart.dates.last(6)

    expect(days.first).to eq(Date.new(2026, 10, 5))
    expect(chart.daily["not_indexed"].last(6)).to eq([1, 1, 2, 1, 1, 1])
    expect(chart.daily["indexed"].last(6)).to eq([0, 0, 0, 1, 1, 1])
    expect(chart.daily["indexed"][-7]).to be_nil
  end

  it "narrows to submitted, unsubmitted or one sitemap's pages" do
    expect([indexing(indexing_pages: "submitted").indexed, indexing(indexing_pages: "submitted").not_indexed]).to eq([1, 0])
    expect([indexing(indexing_pages: "unsubmitted").indexed, indexing(indexing_pages: "unsubmitted").not_indexed]).to eq([0, 1])
    expect(indexing(indexing_pages: sitemap).daily["indexed"].last).to eq(1)
    expect(indexing(indexing_pages: "https://elsewhere.example.com/x.xml").pages).to eq("all")
  end

  it "says why pages aren't indexed" do
    expect(indexing.reasons.map(&:to_h)).to eq([{coverage_state: "Crawled - currently not indexed", count: 1}])
  end

  it "shows any series but never none" do
    expect(indexing.shown).to eq(%w[not_indexed indexed])
    expect(indexing.toggle("indexed")).to eq("not_indexed")
    expect(indexing.toggle("impressions")).to eq("not_indexed,indexed,impressions")
    only = indexing(indexing_show: "not_indexed")
    expect(only.shown).to eq(["not_indexed"])
    expect(only.toggle("not_indexed")).to eq("not_indexed")
    expect(only.toggle("indexed")).to eq("")
    with = indexing(indexing_show: "indexed,impressions")
    expect(with.toggle("impressions")).to eq("indexed")
  end

  it "totals web impressions of the pages picked by day, nil on days not synced" do
    day = Date.new(2026, 10, 9)
    [Date.new(2026, 10, 8), day].each do |date|
      Google::SearchConsole::Stat.create!(date: date, page: nil, page_path: nil, impressions: 99)
    end
    Google::SearchConsole::Stat.create!(date: day, page: "https://blog.example.com/in", page_path: "/in", impressions: 7)
    Google::SearchConsole::Stat.create!(date: day, page: "https://blog.example.com/out", page_path: "/out", impressions: 5)
    Google::SearchConsole::Stat.create!(date: day, page: "https://blog.example.com/other", page_path: "/other", impressions: 50)

    chart = indexing
    expect(chart.impressions[chart.dates.index(day)]).to eq(12)
    expect(chart.impressions[chart.dates.index(Date.new(2026, 10, 8))]).to eq(0)
    expect(chart.impressions[chart.dates.index(today)]).to be_nil
    expect(indexing(indexing_pages: "submitted").impressions[chart.dates.index(day)]).to eq(7)
  end
end
