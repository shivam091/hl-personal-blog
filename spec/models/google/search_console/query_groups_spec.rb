# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::QueryGroups do
  let(:period) { Period.new({from: "2026-10-09", to: "2026-10-11"}, today: Date.new(2026, 10, 12)) }

  subject(:groups) { described_class.new(period) }

  def gsc(date, **attributes)
    Google::SearchConsole::Stat.create!(search_type: "web", date: date, **attributes)
  end

  before do
    gsc(Date.new(2026, 10, 10), clicks: 40, impressions: 1000, position: 7.0)
    gsc(Date.new(2026, 10, 11), clicks: 10, impressions: 200, position: 7.0)
    gsc(Date.new(2026, 10, 10), query: "harshal ladhe blog", clicks: 5, impressions: 10, position: 1.0)
    gsc(Date.new(2026, 10, 10), query: "css grid", clicks: 3, impressions: 100, position: 8.0)
    gsc(Date.new(2026, 10, 11), query: "css grid", clicks: 1, impressions: 300, position: 4.0)
  end

  it "sums branded and non-branded queries, weighting position by impressions" do
    branded, other = groups.brand_split

    expect([branded.name, branded.queries, branded.clicks, branded.ctr, branded.position]).to eq(["Branded", 1, 5, 0.5, 1.0])
    expect([other.name, other.queries, other.clicks, other.impressions, other.position]).to eq(["Non-branded", 1, 4, 400, 5.0])
  end

  it "reads one country's queries from the query-by-country breakdown" do
    Google::SearchConsole::QueryCountryStat.create!(search_type: "web", date: Date.new(2026, 10, 10), query: "harshal ladhe", country: "IN",
      clicks: 2, impressions: 4, position: 1.0)

    branded, other = described_class.new(period, country: "IN").brand_split

    expect([branded.queries, branded.clicks, other.queries]).to eq([1, 2, 0])
  end

  it "groups queries by intent, first matching kind winning, with the most seen as examples" do
    {"how to fix grid error" => 300, "css vw vs dvw" => 50, "what is css grid" => 40, "css grid tutorial" => 30,
     "grid minmax" => 20}.each do |query, impressions|
      gsc(Date.new(2026, 10, 10), query: query, clicks: 1, impressions: impressions, position: 5.0)
    end

    intents = groups.intent_split.to_h { |group| [group.name, [group.queries, group.top]] }

    expect(intents).to eq(
      "Troubleshooting" => [1, ["how to fix grid error"]],
      "Comparison" => [1, ["css vw vs dvw"]],
      "Question" => [1, ["what is css grid"]],
      "Learning" => [1, ["css grid tutorial"]],
      "Topic" => [3, ["css grid", "grid minmax", "harshal ladhe blog"]]
    )
  end

  it "counts each day's clicks by brand, leaving unsynced days empty" do
    expect(groups.daily_brand_clicks).to eq("Branded" => [nil, 5, 0], "Non-branded" => [nil, 3, 1])
  end
end
