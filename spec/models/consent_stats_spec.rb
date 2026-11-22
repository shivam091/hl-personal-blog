# encoding: UTF-8

require "rails_helper"

RSpec.describe ConsentStats, type: :model do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-12"}) }

  before do
    ConsentChoice.collection.insert_many([
      {"_id" => "2026-10-10", "day" => "2026-10-10", "countries" => {"GB" => {"shown" => 10, "granted" => 3, "denied" => 5, "changed" => 1}, "DE" => {"shown" => 2, "granted" => 3}}},
      {"_id" => "2026-10-11", "day" => "2026-10-11", "countries" => {"GB" => {"shown" => 5, "granted" => 1, "denied" => 1}}},
      {"_id" => "2026-10-20", "day" => "2026-10-20", "countries" => {"GB" => {"shown" => 99}}}
    ])
    PageView.collection.insert_many([
      {"_id" => "/a", "slug" => "/a", "consentByDay" => {"2026-10-10" => {"granted" => 20, "denied" => 10, "unset" => 70}, "2026-10-11" => {"denied" => 5, "unset" => 45}, "2026-10-20" => {"denied" => 9}}},
      {"_id" => "/b", "slug" => "/b", "consentByDay" => {"2026-10-10" => {"denied" => 2, "unset" => 8}}},
      {"_id" => "/old", "slug" => "/old"}
    ])
  end

  describe "the banner funnel" do
    it "adds each country's events over the period, busiest first" do
      rows = ConsentStats.new(period).countries

      expect(rows.map { |row| [row.country, row.shown, row.granted, row.denied, row.changed] })
        .to eq([["GB", 15, 4, 6, 1], ["DE", 2, 3, 0, 0]])
    end

    it "works out no answer and the acceptance rate, flooring a negative no answer at none" do
      gb, de = ConsentStats.new(period).countries

      expect(gb.no_answer).to eq(5)
      expect(gb.acceptance_rate).to eq(0.4)
      expect(de.no_answer).to eq(0)
      expect(ConsentStats::Funnel.new(country: "FR", shown: 0, granted: 0, denied: 0, changed: 0).acceptance_rate).to be_nil
    end

    it "totals every country, or keeps to the one picked" do
      expect(ConsentStats.new(period).total.to_h).to include(shown: 17, granted: 7, denied: 6)
      expect(ConsentStats.new(period, country: "DE").countries.map(&:country)).to eq(["DE"])
    end

    it "reports whether anything was recorded and since when" do
      expect(ConsentStats.new(period)).to be_any
      expect(ConsentStats.new(Period.new({from: "2026-09-01", to: "2026-09-02"}))).not_to be_any
      expect(ConsentStats.new(period).recording_since).to eq(Date.new(2026, 10, 10))
    end
  end

  describe "views by consent state" do
    it "adds every page's views over the period, leaving out pages without a split" do
      stats = ConsentStats.new(period)

      expect(stats.views_by_state).to eq("granted" => 20, "denied" => 17, "unset" => 123)
      expect(stats.tracked_views).to eq(160)
      expect(stats.denied_share).to eq(17.0 / 160)
      expect(stats.views_tracked_since).to eq(Date.new(2026, 10, 10))
    end

    it "has no denied share without views" do
      PageView.collection.delete_many({})

      expect(ConsentStats.new(period).denied_share).to be_nil
    end
  end

  describe "#gap" do
    let(:first_party) { {Date.new(2026, 10, 10) => 100, Date.new(2026, 10, 11) => 50, Date.new(2026, 10, 12) => 40} }

    it "has none without GA's figures" do
      expect(ConsentStats.new(period).gap(first_party, nil)).to be_nil
    end

    it "sets our views against GA's on the days both are known, newest first" do
      analytics = {Date.new(2026, 10, 10) => 70, Date.new(2026, 10, 11) => 45, Date.new(2026, 10, 12) => 38}
      gap = ConsentStats.new(period).gap(first_party, analytics)

      # The 12th has no consent split, so it's left out rather than read as a gap.
      expect(gap.days.map(&:date)).to eq([Date.new(2026, 10, 11), Date.new(2026, 10, 10)])
      expect([gap.first_party, gap.analytics, gap.difference, gap.denied]).to eq([150, 115, 35, 17])
      expect(gap.percent).to eq(35.0 / 150)
    end

    it "credits declines with at most the size of the gap" do
      analytics = {Date.new(2026, 10, 10) => 70, Date.new(2026, 10, 11) => 45}
      gap = ConsentStats.new(period).gap(first_party, analytics)

      expect([gap.explained, gap.unexplained]).to eq([17, 18])
      expect(gap.explained_share).to eq(17.0 / 35)

      small = ConsentStats.new(period).gap(first_party, {Date.new(2026, 10, 10) => 99})
      expect([small.difference, small.explained, small.unexplained]).to eq([1, 1, 0])
    end

    it "explains nothing when GA counts more than we do" do
      gap = ConsentStats.new(period).gap(first_party, {Date.new(2026, 10, 10) => 120})

      expect([gap.difference, gap.explained, gap.unexplained, gap.explained_share]).to eq([-20, 0, 0, nil])
    end
  end

  it "exports the funnel with a row for the total" do
    csv = CSV.parse(ConsentStats.new(period).to_csv, headers: true)

    expect(csv.map { |row| [row["Country"], row["Banner shown"], row["Acceptance rate"]] }).to eq([["GB", "15", "0.4"], ["DE", "2", "1.0"], ["All", "17", "0.5385"]])
  end
end
