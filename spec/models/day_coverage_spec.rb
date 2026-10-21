# encoding: UTF-8

require "rails_helper"

RSpec.describe DayCoverage, type: :model do
  let(:dates) { (Date.new(2026, 10, 1)..Date.new(2026, 10, 5)).to_a }

  it "counts every day without figures as missing on a source with no start of its own" do
    source = described_class.new("Blog views", [Date.new(2026, 10, 2)])

    expect(dates.map { source.state(it) }).to eq(%i[missing present missing missing missing])
    expect(source.missing(dates)).to eq(4)
    expect(source.recorded_since(dates)).to be_nil
  end

  it "tells a tally's days before it began from those it missed" do
    source = described_class.new("Consent split", [Date.new(2026, 10, 3)], tally: true, since: Date.new(2026, 10, 3))

    expect(dates.map { source.state(it) }).to eq(%i[before before present missing missing])
    expect(source.missing(dates)).to eq(2)
    expect(source.label(dates.first)).to eq("Not recorded yet")
    expect(source.recorded_since(dates)).to eq(Date.new(2026, 10, 3))
    expect(source.recorded?(dates.first(2))).to be(false)
  end

  it "reads a quiet day on a tally that only writes what it finds as nothing found" do
    source = described_class.new("Automation", [Date.new(2026, 10, 2)], tally: true, since: Date.new(2026, 10, 2), quiet: "Nothing flagged")

    expect(dates.map { source.state(it) }).to eq(%i[before present quiet quiet quiet])
    expect(source.missing(dates)).to eq(0)
    expect(source.label(dates.last)).to eq("Nothing flagged")
  end

  it "treats a tally that hasn't begun as not recorded rather than missing" do
    source = described_class.new("Tag loading", [], tally: true, since: nil)

    expect(source.missing(dates)).to eq(0)
    expect(source.recorded?(dates)).to be(false)
  end

  describe ".tallies" do
    it "reads each tally's days from every page, each from the day it began" do
      PageView.collection.insert_one("_id" => "/a", "slug" => "/a",
        "consentByDay" => {"2026-10-02" => {"granted" => 1}, "2026-10-04" => {"denied" => 1}},
        "gaByDay" => {"2026-10-04" => {"loaded" => 1}}, "suspectByDay" => {"2026-10-03" => {"datacentre" => 2}})

      tallies = described_class.tallies(Period.new({from: "2026-10-01", to: "2026-10-05"})).index_by(&:name)

      expect(dates.map { tallies["Consent split"].state(it) }).to eq(%i[before present missing present missing])
      expect(dates.map { tallies["Tag loading"].state(it) }).to eq(%i[before before before present missing])
      expect(dates.map { tallies["Automation"].state(it) }).to eq(%i[before before present quiet quiet])
    end
  end
end
