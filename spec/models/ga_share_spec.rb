# encoding: UTF-8

require "rails_helper"

RSpec.describe GaShare, type: :model do
  let(:period) { Period.new({from: "2026-10-20", to: "2026-10-26"}) }

  def day(date, first_party, analytics)
    ConsentSnapshot.record(ConsentSnapshot::Inputs.new(date: Date.iso8601(date), first_party: first_party, analytics: analytics,
      states: {}, ga: {}, suspects: {}, banner: nil))
  end

  subject(:share) { described_class.new(period) }

  it "sets the period's share against the days before it" do
    %w[2026-10-13 2026-10-14 2026-10-15 2026-10-16 2026-10-17].each { |date| day(date, 100, 60) }
    %w[2026-10-20 2026-10-21].each { |date| day(date, 100, 40) }

    expect(share).to have_attributes(share: 0.4, usual: 0.6)
    expect(share.usual_basis).to eq("the 14 days before it")
    expect(share).to be_any
  end

  it "falls back on the period's own last days when too few before it are stored" do
    %w[2026-10-20 2026-10-21 2026-10-22 2026-10-23 2026-10-24].each { |date| day(date, 100, 50) }

    expect(share.usual).to eq(0.5)
    expect(share.usual_basis).to start_with("its last 14 days")
  end

  it "works out what GA would have counted at its usual share, leaving days without a count empty" do
    %w[2026-10-13 2026-10-14 2026-10-15 2026-10-16 2026-10-17].each { |date| day(date, 100, 60) }

    expect(share.expected([100, nil, 7])).to eq([60, nil, 4])
  end

  it "has nothing to say without a usual share" do
    day("2026-10-20", 100, 40)

    expect(share.share).to eq(0.4)
    expect(share.usual).to be_nil
    expect(share.expected([100])).to be_nil
    expect(share).not_to be_any
  end
end
