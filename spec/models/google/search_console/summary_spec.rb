# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::Summary do
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }

  def stat(model = Google::SearchConsole::Stat, **attributes)
    model.create!(search_type: "web", **attributes)
  end

  before do
    stat(date: Date.new(2026, 10, 7), clicks: 10, impressions: 400, position: 8.0)
    stat(date: Date.new(2026, 10, 8), clicks: 30, impressions: 600, position: 6.0)
    stat(date: Date.new(2026, 9, 29), clicks: 5, impressions: 100, position: 12.0)
    stat(Google::SearchConsole::CountryStat, date: Date.new(2026, 10, 7), country: "IN", clicks: 7, impressions: 200, position: 5.0)
    stat(date: Date.new(2026, 10, 7), search_type: "image", clicks: 99, impressions: 999, position: 1.0)
    stat(date: Date.new(2026, 10, 7), query: "css grid", clicks: 20, impressions: 500, position: 7.0)
    stat(date: Date.new(2026, 9, 29), query: "css grid", clicks: 2, impressions: 300, position: 11.0)
    stat(date: Date.new(2026, 10, 8), query: "git rebase", clicks: 9, impressions: 40, position: 2.0)
    stat(date: Date.new(2026, 10, 8), query: "rare", clicks: 0, impressions: 60, position: 30.0)
    stat(date: Date.new(2026, 10, 7), page: "https://blog.example.com/post/a", page_path: "/post/a", clicks: 1, impressions: 300, position: 9.0)
    stat(date: Date.new(2026, 10, 7), page: "https://blog.example.com/post/b", page_path: "/post/b", clicks: 30, impressions: 300, position: 3.0)
    stat(date: Date.new(2026, 10, 7), page: "https://blog.example.com/post/a", page_path: "/post/a", query: "css grid",
      clicks: 1, impressions: 250, position: 9.0)
  end

  subject(:summary) { described_class.new(period) }

  it "totals the site's search of every type over the period, position weighted by impressions" do
    totals = summary.totals

    expect([totals.clicks, totals.impressions]).to eq([139, 1999])
    expect(totals.ctr).to be_within(0.0001).of(139.0 / 1999)
    expect(totals.position).to be_within(0.001).of(7799.0 / 1999)
  end

  it "reads one country's totals from the country breakdown" do
    expect(described_class.new(period, country: "IN").totals.clicks).to eq(7)
  end

  it "compares with the period before once there's data from then" do
    expect(summary.previous_totals.clicks).to eq(5)
    expect(described_class.new(Period.new({from: "2026-10-01", to: "2026-10-12"}, today: Date.new(2026, 10, 12))).previous_totals).to be_nil
  end

  it "fills every day of the period, leaving unsynced ones blank" do
    expect(summary.daily(:clicks)).to eq([nil, 109, 30, nil, nil, nil, nil])
  end

  it "ranks queries with their position in the period before" do
    expect(summary.top_queries.map { |row| row[:query] }).to eq(["css grid", "git rebase", "rare"])
    expect(summary.previous_positions["css grid"]).to eq(11.0)
  end

  it "finds queries just off the first page with enough impressions" do
    expect(summary.opportunities.map { |row| row[:query] }).to eq(["css grid"])
  end

  it "finds pages clicked less than the site's average" do
    expect(summary.low_ctr_pages.map { |row| row[:page_path] }).to eq(["/post/a"])
  end

  it "buckets queries by position" do
    expect(summary.position_distribution.transform_values { |row| row[:queries] }).to eq("1–3" => 1, "4–10" => 1, "11–20" => 0, "21+" => 1)
  end

  it "lists a page's own queries and totals" do
    expect(summary.page_queries("/post/a").map { |row| row[:query] }).to eq(["css grid"])
    expect(summary.page_totals("/post/a").impressions).to eq(300)
  end
end
