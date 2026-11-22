# encoding: UTF-8

require "rails_helper"

RSpec.describe ConsentSnapshot, type: :model do
  let(:date) { Date.new(2026, 10, 10) }
  let(:banner) { ConsentStats::Funnel.new(country: "All", shown: 40, granted: 10, denied: 20, changed: 0) }
  let(:states) { {"granted" => 20, "denied" => 30, "pending" => 30, "default" => 20} }
  let(:inputs) do
    ConsentSnapshot::Inputs.new(date: date, first_party: 100, analytics: 30, states: states, ga: {"loaded" => 85, "blocked" => 10},
      suspects: {"datacentre" => 5}, banner: banner)
  end

  describe ".compose" do
    it "puts the gap down to each cause, scaling the ones GA could have seen to the readers it could see" do
      snapshot = described_class.compose(inputs)

      expect(snapshot).to have_attributes(
        day: "2026-10-10", gap: 70, denied_gap: 30, pending_gap: 30, unknown: 5,
        # 40% of readers were visible to GA, so only that share of the blocked, undetected and datacentre views count against it.
        blocked_gap: 4, unknown_gap: 2, datacentre_gap: 2, remainder: 2
      )
      expect(snapshot).to be_complete
    end

    it "works out the ratios the alerts watch" do
      snapshot = described_class.compose(inputs)

      expect(snapshot.ga_ratio).to eq(0.3)
      expect(snapshot.loaded_share).to eq(85.0 / 95)
      expect(snapshot.denied_share).to eq(0.3)
      expect(snapshot.pending_share).to eq(0.3)
      expect(snapshot.acceptance_rate).to eq(1.0 / 3)
      expect(snapshot.banner_per_pending).to eq(40.0 / 30)
    end

    it "leaves ratios out on a day with too few views to say anything" do
      few = ConsentSnapshot::Inputs.new(date: date, first_party: 10, analytics: 8, states: {"denied" => 2, "pending" => 1, "granted" => 7}, ga: {}, suspects: {}, banner: nil)

      expect(described_class.compose(few)).to have_attributes(ga_ratio: nil, denied_share: nil, loaded_share: nil)
    end

    it "cannot explain a day whose views were recorded before pending and default were told apart" do
      legacy = ConsentSnapshot::Inputs.new(date: date, first_party: 100, analytics: 40, states: {"granted" => 20, "unset" => 80}, ga: {}, suspects: {}, banner: nil)
      snapshot = described_class.compose(legacy)

      expect(snapshot).not_to be_complete
      expect(snapshot).to have_attributes(split_recorded: false, remainder: nil, gap: 60)
    end

    it "leaves a cause out on a day its field wasn't recorded, rather than reading it as none" do
      no_ga = ConsentSnapshot::Inputs.new(date: date, first_party: 100, analytics: 30, states: states, ga: {}, suspects: {}, banner: banner)
      snapshot = described_class.compose(no_ga)

      expect(snapshot).to have_attributes(blocked_gap: nil, unknown_gap: nil, datacentre_gap: nil, ga_recorded: false, suspects_recorded: false, remainder: 10)
    end

    it "cannot explain a day GA hasn't synced" do
      unsynced = ConsentSnapshot::Inputs.new(date: date, first_party: 100, analytics: nil, states: states, ga: {}, suspects: {}, banner: banner)

      expect(described_class.compose(unsynced)).not_to be_complete
    end
  end

  describe ".record" do
    it "stores a day once however often it is written" do
      2.times { described_class.record(inputs) }

      expect(described_class.count).to eq(1)
      expect(described_class.first).to have_attributes(day: "2026-10-10", remainder: 2)
    end

    it "keeps GA's figure when a later run finds GA hasn't it" do
      described_class.record(inputs)
      described_class.record(ConsentSnapshot::Inputs.new(date: date, first_party: 120, analytics: nil, states: states, ga: {}, suspects: {}, banner: banner))

      expect(described_class.first).to have_attributes(analytics: 30, gap: 70, first_party: 120)
    end

    it "takes GA's revised figure when it has one" do
      described_class.record(inputs)
      described_class.record(ConsentSnapshot::Inputs.new(date: date, first_party: 100, analytics: 35, states: states, ga: {}, suspects: {}, banner: banner))

      expect(described_class.first).to have_attributes(analytics: 35, gap: 65)
    end
  end

  describe ".stored" do
    it "finds the snapshots inside a period by day" do
      described_class.record(inputs)
      described_class.record(ConsentSnapshot::Inputs.new(date: Date.new(2026, 10, 20), first_party: 5, analytics: 5, states: {}, ga: {}, suspects: {}, banner: nil))

      expect(described_class.stored(Period.new({from: "2026-10-09", to: "2026-10-12"})).keys).to eq(["2026-10-10"])
    end
  end

  describe ".usual" do
    def day(date, first_party, analytics)
      described_class.record(ConsentSnapshot::Inputs.new(date: date, first_party: first_party, analytics: analytics, states: {}, ga: {}, suspects: {}, banner: nil))
    end

    it "takes the median over the settled days before the one judged, skipping days without the measure" do
      [0.5, 0.6, 0.9, 0.4, 0.55].each_with_index { |share, index| day(date - (index + 1), 100, (share * 100).round) }
      day(date - 6, 10, 1)
      day(date, 100, 10)

      expect(described_class.usual(:ga_ratio, date)).to eq(0.55)
    end

    it "has no usual with too few days to call one" do
      4.times { |index| day(date - (index + 1), 100, 50) }

      expect(described_class.usual(:ga_ratio, date)).to be_nil
    end

    it "leaves out days older than the baseline" do
      5.times { |index| day(date - (index + 1), 100, 50) }
      day(date - 20, 100, 99)

      expect(described_class.usual(:ga_ratio, date)).to eq(0.5)
    end
  end

  describe ".ga_share" do
    let(:period) { Period.new({from: "2026-10-01", to: "2026-10-31"}) }

    def day(date, first_party, analytics)
      described_class.record(ConsentSnapshot::Inputs.new(date: date, first_party: first_party, analytics: analytics, states: {}, ga: {}, suspects: {}, banner: nil))
    end

    it "divides GA's views by ours over the days GA has figures for" do
      day(Date.new(2026, 10, 2), 100, 50)
      day(Date.new(2026, 10, 3), 300, 210)
      day(Date.new(2026, 10, 4), 500, nil)

      expect(described_class.ga_share(period)).to eq(0.65)
    end

    it "has no share with too few views to go on" do
      day(Date.new(2026, 10, 2), 20, 10)

      expect(described_class.ga_share(period)).to be_nil
    end
  end

  describe ".precise?" do
    it "is true only when no view is still in the old unset state and some are split" do
      expect(described_class.precise?("pending" => 1)).to be(true)
      expect(described_class.precise?("pending" => 1, "unset" => 1)).to be(false)
      expect(described_class.precise?({})).to be(false)
      expect(described_class.precise?(nil)).to be(false)
    end
  end
end
