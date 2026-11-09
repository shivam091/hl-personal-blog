# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::GenerativeAiSummary do
  let(:today) { Date.new(2026, 10, 12) }
  let(:stats) { Google::SearchConsole::GenerativeAiStat }
  let(:rows) { Google::SearchConsole::GenerativeAiRow }

  def summary(params = {from: "2026-10-05", to: "2026-10-11"})
    described_class.new(Period.new(params, today: today, countries: true))
  end

  def row(breakdown, label, impressions, country: nil, search_type: "Web")
    rows.create!(search_type: search_type, from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30), breakdown: breakdown,
      label: label, impressions: impressions, country: country)
  end

  it "has nothing before any upload" do
    expect(summary.any?).to be(false)
    expect([summary.total, summary.previous_total, summary.covered, summary.pages, summary.countries]).to eq([nil, nil, nil, {}, {}])
  end

  it "totals the period's uploaded days, with none for days not uploaded" do
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 6), impressions: 4)
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 7), impressions: 6)

    expect(summary.total).to eq(10)
    expect(summary.daily).to eq([nil, 4, 6, nil, nil, nil, nil])
    expect(summary.total(Period.new({from: "2026-09-01", to: "2026-09-07"}, today: today))).to be_nil
  end

  it "compares with the period before only once days from before it are uploaded" do
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 6), impressions: 4)
    expect(summary.previous_total).to be_nil

    stats.create!(search_type: "Web", date: Date.new(2026, 9, 28), impressions: 2)
    expect(summary.previous_total).to eq(2)
    expect(summary(from: "2026-10-05", to: "2026-10-11", compare: "country", vs: "US").previous_total).to be_nil
  end

  # Google doesn't say whether one search type's impressions are another's,
  # so they're never added together.
  it "reads the search type with the most days, as the Generative AI page opens on" do
    stats.create!(search_type: "Web (multimodal)", date: Date.new(2026, 10, 6), impressions: 50)
    stats.create!(search_type: "Web (text-based)", date: Date.new(2026, 10, 6), impressions: 4)
    stats.create!(search_type: "Web (text-based)", date: Date.new(2026, 10, 7), impressions: 6)

    expect([summary.search_type, summary.total]).to eq(["Web (text-based)", 10])
  end

  it "dates the latest upload by its breakdowns, and calls it stale once its last day is long past" do
    stats.create!(search_type: "Web", date: Date.new(2026, 9, 30), impressions: 4)
    row("pages", "https://blog.example.com/", 2)

    # An id's time is the system clock's, which travel_to doesn't move.
    expect(summary.uploaded_at).to be_within(1.minute).of(Time.current)
    expect(summary.stale?(today: Date.new(2026, 10, 9))).to be(false)
    expect(summary.stale?(today: Date.new(2026, 10, 12))).to be(true)
  end

  it "gives the latest upload's pages by path and countries by code, with the range they cover" do
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 6), impressions: 4)
    row("pages", "https://blog.example.com/post/grid", 6)
    row("pages", "https://blog.example.com/", 2)
    row("countries", "India", 5, country: "IN")
    row("countries", "Atlantis", 1)
    row("pages", "https://blog.example.com/post/other", 9, search_type: "Web (multimodal)")

    expect(summary.covered).to eq(Date.new(2026, 9, 1)..Date.new(2026, 9, 30))
    expect(summary.pages).to eq("/post/grid" => 6, "/" => 2)
    expect(summary.countries).to eq("IN" => 5)
  end
end
