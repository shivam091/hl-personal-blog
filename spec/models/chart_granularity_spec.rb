# encoding: UTF-8

require "rails_helper"

RSpec.describe ChartGranularity do
  let(:days) { (Date.new(2026, 9, 28)..Date.new(2026, 10, 6)).to_a }

  it "sums days into Monday weeks, leaving a bucket with nothing known blank" do
    weeks = described_class.new(chart_by: "week")

    expect(weeks.dates(days)).to eq([Date.new(2026, 9, 28), Date.new(2026, 10, 5)])
    expect(weeks.sums(days, [1] * 7 + [nil, nil])).to eq([7, nil])
    expect(weeks.events(Date.new(2026, 10, 6) => ["A"], Date.new(2026, 10, 5) => ["B"])).to eq(Date.new(2026, 10, 5) => %w[A B])
    expect(weeks.query).to eq(chart_by: "week")
  end

  it "falls back to days, which keep URLs clean" do
    days_by = described_class.new(chart_by: "fortnight")

    expect([days_by.by, days_by.query]).to eq(["day", {}])
  end
end
