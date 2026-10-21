# encoding: UTF-8

require "rails_helper"

RSpec.describe PageGap, type: :model do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-12"}) }

  def page(slug, views)
    PageView.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => {"2026-10-10" => {"IN" => views}, "2026-10-20" => {"IN" => 999}})
  end

  def analytics(path, views)
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: path, views: views)
  end

  before do
    # Five ordinary pages losing 20%, and one losing 80%.
    %w[/a /b /c /d /e].each_with_index do |slug, index|
      page(slug, 100)
      analytics(index.even? ? "#{slug}/" : slug, 80)
    end
    page("/broken", 100)
    analytics("/broken?utm_source=x", 20)
    page("/quiet", 5)
    analytics("/quiet", 5)
    analytics("/only-ga", 7)
  end

  subject(:gap) { described_class.new(period) }

  it "sets each page's views against GA's, naming a page the way the blog does" do
    row = gap.rows.find { |candidate| candidate.slug == "/a" }

    expect(row).to have_attributes(first_party: 100, analytics: 80, gap: 20, percent: 0.2)
    expect(gap.rows.map(&:slug)).to include("/c", "/broken", "/only-ga")
  end

  it "counts only the days GA has synced" do
    expect(gap.rows.find { |row| row.slug == "/a" }.first_party).to eq(100)
    expect(gap.days_covered).to eq(1)
  end

  it "flags a page losing far more than the median, and no others" do
    expect(gap.median_percent).to eq(0.2)
    expect(gap.flagged.map(&:slug)).to eq(["/broken"])
  end

  it "judges only the pages busy enough, flagging from the median plus the margin" do
    expect(gap.judged.map(&:slug)).to contain_exactly("/a", "/b", "/c", "/d", "/e", "/broken")
    expect(gap.threshold).to be_within(1e-9).of(0.4)
  end

  it "ranks the pages GA missed most views on, against every view it missed" do
    expect(gap.missing(3).map { |row| [row.slug, row.gap] }).to eq([["/broken", 80], ["/a", 20], ["/b", 20]])
    expect(gap.missing.map(&:slug)).not_to include("/quiet", "/only-ga")
    expect(gap.missing_total).to eq(180)
  end

  it "lists the flagged pages costing most views first" do
    page("/worse", 300)
    analytics("/worse", 30)

    expect(gap.top_flagged.map(&:slug)).to eq(["/worse", "/broken"])
    expect(gap.top_flagged(1).map(&:slug)).to eq(["/worse"])
  end

  describe "#causes" do
    def split(slug, consent:, ga: nil, suspects: nil)
      fields = {"consentByDay" => {"2026-10-10" => consent}, "gaByDay" => ({"2026-10-10" => ga} if ga), "suspectByDay" => ({"2026-10-10" => suspects} if suspects)}
      PageView.collection.update_one({"_id" => slug}, {"$set" => fields.compact})
    end

    it "puts a page's gap down to causes by the snapshot's rules, counting blocked and the rest only for readers GA could see" do
      split("/broken", consent: {"granted" => 40, "denied" => 40, "pending" => 20}, ga: {"loaded" => 60, "blocked" => 30}, suspects: {"datacentre" => 10})

      causes = gap.causes(["/broken"]).fetch("/broken")

      expect(causes.days.size).to eq(1)
      expect(ConsentSnapshot::BUCKETS.to_h { |bucket| [bucket, causes.sum(bucket)] })
        .to eq(denied_gap: 40, pending_gap: 20, blocked_gap: 12, unknown_gap: 4, datacentre_gap: 4)
      expect([causes.gap, causes.remainder]).to eq([80, 0])
    end

    it "leaves out a page whose days lack the consent split" do
      split("/a", consent: {"unset" => 100})

      expect(gap.causes(%w[/a /b])).to be_empty
    end
  end

  it "gives each page's share lost by week, leaving a week too quiet to judge empty" do
    PageView.collection.update_one({"_id" => "/broken"}, {"$set" => {"countriesByDay.2026-10-12" => {"IN" => 10}}})
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 12), page_path: "/broken", views: 10)

    wide = described_class.new(Period.new({from: "2026-10-01", to: "2026-10-12"}))

    expect(wide.weeks).to eq([Date.new(2026, 9, 28), Date.new(2026, 10, 5), Date.new(2026, 10, 12)])
    expect(wide.weekly_percents("/broken")).to eq([nil, 0.8, nil])
    expect(wide.weekly_percents("/missing")).to eq([nil, nil, nil])
  end

  it "gives no share to a page too quiet to judge or one GA counted alone" do
    expect(gap.rows.find { |row| row.slug == "/quiet" }.percent).to be_nil
    expect(gap.rows.find { |row| row.slug == "/only-ga" }).to have_attributes(first_party: 0, percent: nil)
  end

  it "exports every page with its flag" do
    csv = CSV.parse(gap.to_csv, headers: true)
    broken = csv.find { |row| row["Page"] == "/broken" }

    expect(broken.to_h).to include("Our views" => "100", "GA views" => "20", "Gap" => "80", "Well above the median" => "yes")
  end

  it "has nothing to compare before GA has synced" do
    Google::Analytics::Stat.delete_all

    expect(gap).not_to be_any
  end
end
