# encoding: UTF-8

require "rails_helper"

RSpec.describe ConsentGap, type: :model do
  def snapshot(date, first_party:, analytics:, **inputs)
    ConsentSnapshot.compose(ConsentSnapshot::Inputs.new(
      date: Date.iso8601(date), first_party: first_party, analytics: analytics, states: inputs.fetch(:states, {"denied" => 20, "pending" => 10, "granted" => 70}),
      ga: inputs.fetch(:ga, {"loaded" => 80, "blocked" => 10}), suspects: inputs.fetch(:suspects, {}), banner: nil
    ))
  end

  let(:days) do
    [
      snapshot("2026-10-11", first_party: 100, analytics: 50),
      snapshot("2026-10-10", first_party: 100, analytics: 60),
      snapshot("2026-10-09", first_party: 100, analytics: 40, states: {"unset" => 100})
    ]
  end

  subject(:gap) { described_class.new(days) }

  it "adds up only the days the consent split lets it explain" do
    expect(gap.days.size).to eq(2)
    expect(gap).to have_attributes(first_party: 200, analytics: 110, gap: 90)
    expect(gap.percent).to eq(0.45)
  end

  it "adds each cause and leaves what they don't account for as the remainder" do
    expect(gap.sum(:denied_gap)).to eq(40)
    expect(gap.sum(:pending_gap)).to eq(20)
    # 70% of readers were visible to GA, so 7 of each day's 10 blocked and 7 of its 10 undetected views count.
    expect(gap.sum(:blocked_gap)).to eq(14)
    expect(gap.sum(:unknown_gap)).to eq(14)
    expect(gap.remainder).to eq(90 - 40 - 20 - 14 - 14)
    expect(gap.share_of_gap(:denied_gap)).to eq(40.0 / 90)
    expect(gap.remainder_share).to eq(gap.remainder.fdiv(90))
  end

  it "says so when the causes found add up to more than the gap" do
    over = described_class.new([snapshot("2026-10-11", first_party: 100, analytics: 90)])

    expect(over).to be_over_counted
    expect(over.remainder).to be_negative
  end

  it "counts the days that couldn't say whether the tag loaded" do
    mixed = described_class.new([snapshot("2026-10-11", first_party: 100, analytics: 50), snapshot("2026-10-10", first_party: 100, analytics: 50, ga: {})])

    expect(mixed.days_missing(:ga_recorded)).to eq(1)
  end

  it "has no shares without a gap" do
    flat = described_class.new([snapshot("2026-10-11", first_party: 100, analytics: 100)])

    expect(flat.remainder_share).to be_nil
    expect(flat.share_of_gap(:denied_gap)).to be_nil
    expect(described_class.new([])).not_to be_any
  end
end
