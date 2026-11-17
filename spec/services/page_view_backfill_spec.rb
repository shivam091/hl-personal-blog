# encoding: UTF-8

require "rails_helper"

RSpec.describe PageViewBackfill do
  def ga(date, path, country, views, users)
    Google::Analytics::CountryStat.create!(date: Date.iso8601(date), page_path: path, country: country, views: views, active_users: users)
  end

  def page(slug, counts = {})
    PageView.collection.insert_one("_id" => slug, "slug" => slug, "url" => "https://blog.example.com#{slug}", "countriesByDay" => counts,
      "visitorCount" => counts.values.sum { |day| day.values.sum }, "uniqueVisitorCount" => 0)
  end

  def device(date, path, device, views)
    Google::Analytics::DeviceStat.create!(date: Date.iso8601(date), page_path: path, device: device, views: views)
  end

  def referrer(date, path, referrer, views)
    Google::Analytics::ReferrerStat.create!(date: Date.iso8601(date), page_path: path, referrer: referrer, views: views)
  end

  def marker(slug, day, hash)
    PageViewSeen.collection.insert_one("slug" => slug, "day" => day, "ipHash" => hash, "country" => "IN", "at" => Time.utc(2026, 10, 10))
  end

  # Over the overlap the blog counted 3 views and 2 visitors to GA's 4 and 4,
  # and a bot-hit day is left out of that.
  before do
    page("/a", "2026-10-10" => {"IN" => 3}, "2026-10-11" => {"IN" => 50})
    marker("/a", "2026-10-10", "x1")
    marker("/a", "2026-10-10", "x2")
    ga("2026-10-10", "/a", "IN", 4, 4)
    ga("2026-10-11", "/a", "IN", 5, 5)
    ga("2026-09-01", "/a", "IN", 8, 4)
    ga("2026-09-01", "/a", "US", 4, 4)
    ga("2026-09-02", "/gone", "IN", 6, 3)
  end

  context "with devices and referrers" do
    before do
      device("2026-09-01", "/a", "desktop", 8)
      device("2026-09-01", "/a", "mobile", 4)
      device("2026-10-10", "/a", "desktop", 3)
      device("2026-10-10", "/a", "mobile", 1)
      referrer("2026-09-01", "/a", "(not set)", 6)
      referrer("2026-09-01", "/a", "https://blog.example.com/x", 3)
      referrer("2026-09-01", "/a", "https://www.google.com/", 3)
    end

    it "splits each estimated day's views as Google Analytics splits the day, keyed as the blog keys them" do
      result = described_class.call(write: true)

      stored = PageView.find("/a")
      expect(stored.devices_by_day["2026-09-01"]).to eq("desktop" => 6, "mobile" => 3)
      expect(stored.referrers_by_day["2026-09-01"]).to eq("direct" => 5, "internal" => 2, "google_com" => 2)
      expect(result.breakdown_days).to eq(2)
    end

    it "fills the blog's own days from before it dated devices and referrers, to the views it counted" do
      described_class.call(write: true)

      expect(PageView.find("/a").devices_by_day["2026-10-10"]).to eq("desktop" => 2, "mobile" => 1)
    end

    it "leaves a day Google Analytics has no split for undated" do
      described_class.call(write: true)

      expect(PageView.find("/a").devices_by_day).not_to have_key("2026-10-11")
    end

    it "reverts them too" do
      described_class.call(write: true)

      described_class.revert

      expect(PageView.find("/a").devices_by_day).to be_empty
      expect(PageView.find("/a").referrers_by_day).to be_empty
    end
  end

  it "scales Google Analytics views and visitors by how the blog's own compare, leaving bot days out of that" do
    result = described_class.call

    expect(result.views_factor).to eq(0.75)
    expect(result.visitors_factor).to eq(0.5)
  end

  it "writes nothing unless asked" do
    described_class.call

    expect(PageView.find("/a").countries_by_day.keys).to eq(%w[2026-10-10 2026-10-11])
  end

  it "adds dated countries, the totals and a visitor marker per estimated visitor, for pages the blog has" do
    result = described_class.call(write: true)

    stored = PageView.find("/a")
    expect(stored.countries_by_day["2026-09-01"]).to eq("IN" => 6, "US" => 3)
    expect(stored.visitor_count).to eq(53 + 9)
    expect(stored.unique_visitor_count).to eq(4)
    markers = PageViewSeen.where(ipHash: /\Abackfill:/)
    expect(markers.where(day: "2026-09-01").map(&:country).tally).to eq("IN" => 2, "US" => 2)
    expect(result.skipped_views).to eq(6)
    expect(PageView.where(slug: "/gone")).to be_empty
  end

  it "keeps the estimated visitors from outnumbering the views" do
    ga("2026-09-03", "/a", "IN", 1, 5)

    described_class.call(write: true)

    expect(PageViewSeen.where(day: "2026-09-03", ipHash: /\Abackfill:/).count).to be <= 1
  end

  it "won't backfill twice" do
    described_class.call(write: true)

    expect { described_class.call(write: true) }.to raise_error(/Already backfilled/)
  end

  it "reverts to what the blog counted itself" do
    described_class.call(write: true)

    described_class.revert

    stored = PageView.find("/a")
    expect(stored.countries_by_day.keys).to eq(%w[2026-10-10 2026-10-11])
    expect(stored.visitor_count).to eq(53)
    expect(stored.unique_visitor_count).to eq(0)
    expect(PageViewSeen.pluck(:ip_hash)).to contain_exactly("x1", "x2")
  end
end
