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
