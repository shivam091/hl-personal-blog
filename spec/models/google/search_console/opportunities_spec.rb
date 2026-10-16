# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::Opportunities do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({}, today: today) }
  let(:now) { Date.new(2026, 10, 1) }
  let(:before) { Date.new(2026, 9, 1) }

  def query(text, position:, impressions:, clicks:)
    search_console_row(
      date: now,
      query: text,
      position: position,
      impressions: impressions,
      clicks: clicks
    )
  end

  def page(path, date:, clicks:, impressions:, position:)
    search_console_row(
      date: date,
      page: "https://blog.example.com#{path}",
      page_path: path,
      clicks: clicks,
      impressions: impressions,
      position: position
    )
  end

  before do
    # Older than the period before, so that period reads as synced.
    search_console_row(date: Date.new(2026, 8, 1), clicks: 1, impressions: 1)
    query("css grid", position: 3.0, impressions: 200, clicks: 40)
    query("retitle me", position: 5.0, impressions: 1000, clicks: 2)
    query("neighbour", position: 5.5, impressions: 100, clicks: 30)
    query("subgrid", position: 8.0, impressions: 500, clicks: 5)
    query("flex gap", position: 12.0, impressions: 100, clicks: 0)
    query("too far", position: 30.0, impressions: 900, clicks: 0)
    %w[/post/grid /post/subgrid].zip([400, 100]).each do |path, impressions|
      search_console_row(
        date: now,
        query: "subgrid",
        page: "https://blog.example.com#{path}",
        page_path: path,
        impressions: impressions,
        clicks: 1,
        position: 8.0
      )
    end
    page("/post/grid", date: before, clicks: 50, impressions: 1000, position: 3.0)
    page("/post/grid", date: now, clicks: 20, impressions: 1000, position: 6.0)
    page("/post/flex", date: before, clicks: 20, impressions: 500, position: 5.0)
    page("/post/flex", date: now, clicks: 18, impressions: 500, position: 5.0)
    page("/post/gone", date: before, clicks: 12, impressions: 300, position: 7.0)
  end

  subject(:opportunities) { described_class.new(period) }

  it "lists queries near the first page by the clicks a top-3 spot would bring, with the page that ranks" do
    rows = opportunities.striking_distance

    expect(opportunities.target_ctr).to eq(0.2)
    expect(rows.map { |row| [row.query, row.potential_clicks] }).to eq(
      [["retitle me", 198], ["subgrid", 95], ["flex gap", 20], ["neighbour", 0]]
    )
    expect(rows.find { |row| row.query == "subgrid" }.page_path).to eq("/post/grid")
    expect(rows.select(&:low_ctr).map(&:query)).to eq(["retitle me"])
  end

  it "lists pages that lost a real share of their clicks, with the likeliest cause" do
    rows = opportunities.losing_pages

    expect(rows.map { |row| [row.page_path, row.lost, row.cause] }).to eq(
      [["/post/grid", 30, "Ranking dropped"], ["/post/gone", 12, "Fewer searches"]]
    )
  end

  it "exports both lists" do
    expect(CSV.parse(opportunities.to_csv("striking")).second).to eq(
      ["retitle me", nil, "2", "1000", "0.002", "5.0", "0.0291", "Yes", "198", "0", nil]
    )
    expect(CSV.parse(opportunities.to_csv("losing")).second).to eq(
      ["/post/grid", "20", "50", "30", "1000", "1000", "6.0", "3.0", "Ranking dropped"]
    )
  end
end
