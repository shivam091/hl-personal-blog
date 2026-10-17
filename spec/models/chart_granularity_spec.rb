# encoding: UTF-8

require "rails_helper"

RSpec.describe ChartGranularity do
  let(:days) { (Date.new(2026, 9, 28)..Date.new(2026, 10, 6)).to_a }

  it "sums days into Monday weeks, leaving a bucket with nothing known blank" do
    weeks = described_class.new({chart_by: "week"})

    expect(weeks.dates(days)).to eq([Date.new(2026, 9, 28), Date.new(2026, 10, 5)])
    expect(weeks.sums(days, [1] * 7 + [nil, nil])).to eq([7, nil])
    expect(weeks.events(Date.new(2026, 10, 6) => ["A"], Date.new(2026, 10, 5) => ["B"])).to eq(Date.new(2026, 10, 5) => %w[A B])
    expect(weeks.query).to eq(chart_by: "week")
  end

  it "sums days into calendar years" do
    years = described_class.new({chart_by: "year"})
    dates = [Date.new(2025, 12, 31), Date.new(2026, 1, 1), Date.new(2026, 6, 1)]

    expect(years.dates(dates)).to eq([Date.new(2025, 1, 1), Date.new(2026, 1, 1)])
    expect(years.sums(dates, [1, 2, 3])).to eq([1, 5])
  end

  it "buckets another period's days as it does this one's, and starts weeks on the day asked" do
    weeks = described_class.new({chart_by: "week"})
    period = Struct.new(:from, :to).new(days.first, days.last)

    expect(weeks.sums_for(period, [1] * 9)).to eq([7, 2])
    expect(described_class.buckets(:sunday).fetch("week").(Date.new(2026, 10, 6))).to eq(Date.new(2026, 10, 4))
    expect(described_class::OPTIONS.map(&:last)).to eq(%w[day week month year])
  end

  it "falls back to days, which keep URLs clean" do
    days_by = described_class.new({chart_by: "fortnight"})

    expect([days_by.by, days_by.query]).to eq(["day", {}])
  end

  describe "for the period's length" do
    def period(days)
      Struct.new(:days).new(days)
    end

    it "offers only the buckets the period is longer than" do
      expect(described_class.allowed(period(1))).to eq(%w[day])
      expect(described_class.allowed(period(7))).to eq(%w[day])
      expect(described_class.allowed(period(28))).to eq(%w[day week])
      expect(described_class.allowed(period(90))).to eq(%w[day week month])
      expect(described_class.allowed(period(486))).to eq(%w[day week month year])
    end

    it "offers no choice where only days are left" do
      expect(described_class.options(period(1))).to eq([])
      expect(described_class.options(period(28))).to eq([%w[Day day], %w[Week week]])
    end

    it "reads a bucket the period is too short for as days" do
      expect(described_class.new({chart_by: "year"}, period: period(7)).by).to eq("day")
      expect(described_class.new({chart_by: "week"}, period: period(28)).by).to eq("week")
    end
  end
end
