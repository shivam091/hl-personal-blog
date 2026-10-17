# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::Summary do
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }

  before do
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 7), page_path: "/post/a", views: 40, sessions: 30, engagement_seconds: 600)
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 7), page_path: "/post/b", views: 10, sessions: 25, engagement_seconds: 150)
    Google::Analytics::Stat.create!(date: Date.new(2026, 9, 29), page_path: "/post/a", views: 5)
    Google::Analytics::LandingPageStat.create!(date: Date.new(2026, 10, 7), page_path: "/post/a", sessions: 30, engaged_sessions: 15)
    Google::Analytics::CountryStat.create!(date: Date.new(2026, 10, 7), page_path: "/post/a", country: "IN", views: 12)
    Google::Analytics::SourceStat.create!(date: Date.new(2026, 10, 7), page_path: "/post/a", channel_group: "Organic Search",
      source: "google", medium: "organic", views: 33)
  end

  subject(:summary) { described_class.new(period) }

  it "adds up views by page, but sessions only from landing pages" do
    expect(summary.views).to eq(50)
    expect(summary.sessions.sessions).to eq(30)
    expect(summary.sessions.engagement_rate).to eq(0.5)
    expect(summary.engagement_seconds_per_session).to eq(25.0)
  end

  it "narrows views to a country" do
    expect(described_class.new(period, country: "IN").views).to eq(12)
    expect(described_class.new(period, country: "IN").daily_views).to eq([nil, 12, nil, nil, nil, nil, nil])
  end

  it "splits views by page and country" do
    expect(summary.pages.transform_values(&:views)).to eq("/post/a" => 40, "/post/b" => 10)
    expect(summary.countries).to eq("IN" => 12)
  end

  it "knows which days were synced" do
    expect(summary.days_with_data).to eq([Date.new(2026, 10, 7)])
    expect(summary.previous?).to be_truthy
  end
end
