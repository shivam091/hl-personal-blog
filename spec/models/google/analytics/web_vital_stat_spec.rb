# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::WebVitalStat do
  def vital(path, metric, rating, count, sum)
    described_class.create!(date: Date.new(2026, 10, 10), page_path: path, metric: metric, rating: rating, event_count: count, value_sum: sum)
  end

  before do
    vital("/a", "LCP", "good", 6, 9000)
    vital("/a", "LCP", "poor", 2, 10_000)
    vital("/a", "LCP", "(not set)", 2, 3000)
    vital("/b", "LCP", "needs-improvement", 12, 36_000)
    vital("/b", "CLS", "good", 4, 0.2)
  end

  it "rates over rated reports only, but averages every report" do
    lcp = described_class.overview(described_class.all).fetch("LCP")

    expect(lcp).to have_attributes(event_count: 22, rated_count: 20, good_count: 6, poor_count: 2, needs_improvement_count: 12)
    expect(lcp.good_share).to eq(0.3)
    expect(lcp.poor_share).to eq(0.1)
    expect(lcp.mean_value).to eq(58_000.0 / 22)
  end

  it "sums a page's rows in the database, deriving the same figures there" do
    rows = described_class.grouped(described_class.where(metric: "LCP"), by: [:page_path]).order(mean_value: :desc).to_a

    expect(rows.map { |row| [row[:page_path], row[:mean_value], row[:poor_share]] }).to eq([["/b", 3000.0, 0.0], ["/a", 2200.0, 0.25]])
  end

  it "ranks the slowest pages only from enough reports" do
    expect(described_class.slowest_pages(described_class.all, "LCP", min_reports: 10).map { |row| row[:page_path] }).to eq(%w[/b /a])
    expect(described_class.slowest_pages(described_class.all, "LCP", min_reports: 11).map { |row| row[:page_path] }).to eq(%w[/b])
  end

  it "scales CLS back on sync, leaving times as they are" do
    result = described_class.sync([
      {date: Date.new(2026, 10, 11), page_path: "/c", metric: "CLS", rating: "good", event_count: 3, value_sum: 150.0},
      {date: Date.new(2026, 10, 11), page_path: "/c", metric: "INP", rating: "good", event_count: 3, value_sum: 150.0}
    ])

    expect(result.created).to eq(2)
    expect(described_class.where(page_path: "/c").order(metric: :asc).pluck(:metric, :value_sum)).to eq([["CLS", 0.15], ["INP", 150.0]])
  end
end
