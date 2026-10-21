# encoding: UTF-8

require "rails_helper"

RSpec.describe PageGapShift, type: :model do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-10", compare: "previous"}) }

  def views(slug, by_day)
    PageView.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => by_day.transform_values { |count| {"IN" => count} })
  end

  def analytics(path, day, count)
    Google::Analytics::Stat.create!(date: Date.iso8601(day), page_path: path, views: count)
  end

  before do
    views("/moved", "2026-10-09" => 100, "2026-10-10" => 100)
    analytics("/moved/", "2026-10-09", 60)
    analytics("/moved/", "2026-10-10", 30)
    views("/steady", "2026-10-09" => 100, "2026-10-10" => 100)
    analytics("/steady", "2026-10-09", 60)
    analytics("/steady", "2026-10-10", 50)
    views("/quiet", "2026-10-09" => 10, "2026-10-10" => 100)
    analytics("/quiet", "2026-10-09", 9)
    analytics("/quiet", "2026-10-10", 20)
  end

  it "marks a page whose share seen by GA moved by the margin, matching GA's address to the blog's" do
    shift = described_class.new(period)["/moved/"]

    expect(shift.before).to be_within(0.001).of(0.6)
    expect(shift.now).to be_within(0.001).of(0.3)
  end

  it "leaves out a page that moved less than the margin, or had too few views in either period" do
    shifts = described_class.new(period)

    expect(shifts["/steady"]).to be_nil
    expect(shifts["/quiet"]).to be_nil
  end

  it "judges nothing without a comparison over time" do
    expect(described_class.new(Period.new({from: "2026-10-10", to: "2026-10-10", compare: "off"})).shifts).to be_empty
  end
end
