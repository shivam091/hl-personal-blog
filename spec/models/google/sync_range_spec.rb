# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SyncRange do
  around { |example| travel_to(Time.zone.local(2026, 10, 12, 12)) { example.run } }

  def messages(range)
    range.validate
    range.errors.full_messages
  end

  it "defaults to the last week" do
    range = described_class.new

    expect([range.from, range.to, range.days]).to eq([Date.new(2026, 10, 6), Date.new(2026, 10, 12), 7])
    expect(range).to be_valid
  end

  it "tells a mistyped date from a missing one" do
    range = described_class.new(from: "garbage", to: "")

    expect(range).not_to be_valid
    expect(range.errors.full_messages).to eq(["Start date is not a valid date", "End date can't be blank"])
  end

  it "refuses an end before the start, or in the future" do
    expect(messages(described_class.new(from: "2026-10-05", to: "2026-10-01"))).to eq(["End date can't be before the start date"])
    expect(messages(described_class.new(from: "2026-10-01", to: "2026-10-13"))).to eq(["End date can't be in the future"])
  end

  it "refuses days older than Google keeps, when it has a limit" do
    range = described_class.new(from: "2025-01-01", to: "2025-01-31", earliest: Date.new(2025, 6, 12))

    expect(messages(range)).to eq(["Start date can't be before 12 Jun, 2025, the oldest day Google keeps"])
    expect(described_class.new(from: "2025-01-01", to: "2025-01-31")).to be_valid
  end
end
