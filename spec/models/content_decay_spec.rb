# encoding: UTF-8

require "rails_helper"

RSpec.describe ContentDecay do
  let(:today) { Date.new(2026, 10, 12) }
  let(:now) { Date.new(2026, 10, 8) }
  let(:before_now) { Date.new(2026, 9, 25) }

  def entry(path, type: "post", updated:)
    FeedEntry.create!(url: "https://blog.example.com#{path}", name: path.delete_prefix("/post/").humanize, type: type,
      published_at: Time.zone.parse("2024-01-01"), last_modified_at: Time.zone.parse(updated))
  end

  def views(path, count)
    PageView.collection.insert_one("_id" => path, "slug" => path, "countriesByDay" => {now.iso8601 => {"IN" => count}})
  end

  def search(path, date:, clicks:, impressions:, position:)
    Google::SearchConsole::Stat.create!(date: date, page: "https://blog.example.com#{path}", page_path: path,
      clicks: clicks, impressions: impressions, position: position)
  end

  def decay(params = {}, **filters)
    period = Period.new({from: "2026-10-01", to: "2026-10-12"}.merge(params), today: today)
    summary = Google::SearchConsole::Summary.new(period)
    described_class.new(ContentStats.new(BlogStats.new(period), search: summary),
      Google::SearchConsole::Opportunities.new(period, summary: summary), today: today, **filters)
  end

  before do
    # Older than the period before, so that period reads as synced.
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 8, 1), clicks: 1, impressions: 1)

    entry("/post/both", updated: "2025-01-01")
    views("/post/both", 50)
    search("/post/both", date: before_now, clicks: 40, impressions: 800, position: 3.0)
    search("/post/both", date: now, clicks: 10, impressions: 800, position: 6.0)

    entry("/post/stale", updated: "2025-06-01")
    views("/post/stale", 90)

    entry("/post/slipping", type: "tutorial", updated: "2026-09-01")
    search("/post/slipping", date: before_now, clicks: 5, impressions: 300, position: 4.0)
    search("/post/slipping", date: now, clicks: 5, impressions: 300, position: 7.5)

    entry("/post/fine", updated: "2025-01-01")
    views("/post/fine", 5)
  end

  it "ranks entries by how many signs of decay they show, saying which" do
    rows = decay.rows

    expect(rows.map { |row| row.item.path }).to eq(%w[/post/both /post/stale /post/slipping])
    expect(rows.first.reasons).to eq(["Not updated in 21 months, still read 50 times", "Lost 30 of 40 search clicks: ranking dropped"])
    expect(rows.first.lost_clicks).to eq(30)
    expect(rows.last.reasons).to eq(["Slipped from position 4.0 to 7.5"])
  end

  it "narrows the queue by type and by time since the last update" do
    expect(decay(type: "tutorial").rows.map { |row| row.item.path }).to eq(%w[/post/slipping])
    expect(decay(min_age_months: "12").rows.map { |row| row.item.path }).to eq(%w[/post/both /post/stale])
  end

  it "leaves search losses out when nothing is compared" do
    report = decay({compare: "off"})

    expect(report.compared?).to be(false)
    expect(report.rows.map { |row| row.item.path }).to eq(%w[/post/stale /post/both])
    expect(report.rows.last.reasons).to eq(["Not updated in 21 months, still read 50 times"])
  end

  it "exports the queue as CSV" do
    rows = CSV.parse(decay.to_csv)

    expect(rows.first).to eq(ContentDecay::CSV_HEADERS)
    expect(rows.second.values_at(0, 1, 7, 8, 9, 12)).to eq(["1", "https://blog.example.com/post/both", "50", "10", "40",
      "Not updated in 21 months, still read 50 times; Lost 30 of 40 search clicks: ranking dropped"])
  end
end
