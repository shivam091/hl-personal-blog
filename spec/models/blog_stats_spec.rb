# encoding: UTF-8

require "rails_helper"

RSpec.describe BlogStats do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: today) }

  # Shaped like the frontend writes them, so the counts are tested against
  # real data.
  before do
    PageView.collection.insert_many([
      {"_id" => "/post/a", "slug" => "/post/a",
       "viewsByDay" => {"2026-10-06" => 4, "2026-09-01" => 9},
       "countriesByDay" => {"2026-10-06" => {"IN" => 1}, "2026-10-08" => {"IN" => 150, "US" => 30}, "2026-10-01" => {"US" => 10}}},
      {"_id" => "/post/b", "slug" => "/post/b",
       "countriesByDay" => {"2026-10-10" => {"unknown" => 2, "DE" => 25}, "not-a-day" => {"IN" => 99}}}
    ])
    PageLike.collection.insert_one(
      "_id" => "/post/a", "slug" => "/post/a", "likeCount" => 10,
      "countriesByDay" => {"2026-10-08" => {"IN" => 6}, "2026-10-01" => {"US" => 1}}
    )
    NewsletterSubscriber.collection.insert_many([
      {"email" => "a@example.com", "country" => "IN", "subscribedAt" => Time.zone.parse("2026-10-07 23:30")},
      {"email" => "b@example.com", "subscribedAt" => Time.zone.parse("2026-10-09 10:00")},
      {"email" => "old@example.com", "country" => "IN", "subscribedAt" => Time.zone.parse("2026-08-01 10:00")}
    ])
    Message.collection.insert_one("name" => "A", "email" => "a@example.com", "message" => "Hi", "country" => "US",
      "createdAt" => Time.zone.parse("2026-10-11 09:00"))
  end

  subject(:stats) { described_class.new(period) }

  it "totals each metric in the period" do
    expect(stats.total(:views)).to eq(4 + 1 + 150 + 30 + 2 + 25)
    expect(stats.total(:likes)).to eq(6)
    expect(stats.total(:subscribers)).to eq(2)
    expect(stats.total(:messages)).to eq(1)
  end

  it "totals the period before for comparison" do
    expect(stats.total(:views, period.previous)).to eq(10)
    expect(stats.total(:likes, period.previous)).to eq(1)
  end

  it "fills every day of the period, quiet ones as zero" do
    expect(stats.daily(:views)).to eq([5, 0, 180, 0, 27, 0, 0])
    expect(stats.daily_by(:views, :slug)["/post/b"]).to eq([0, 0, 0, 0, 27, 0, 0])
    expect(stats.daily_by(:views, :slug)["/post/none"]).to eq([0] * 7)
  end

  it "counts undated views and missing countries as Unknown" do
    expect(stats.by_country(:views)).to eq("ZZ" => 6, "IN" => 151, "US" => 30, "DE" => 25)
    expect(stats.by_country(:subscribers)).to eq("IN" => 1, "ZZ" => 1)
  end

  it "narrows every figure to one country" do
    in_india = described_class.new(period, country: "IN")

    expect(in_india.total(:views)).to eq(151)
    expect(in_india.total(:subscribers)).to eq(1)
    expect(in_india.by_page(:views)).to eq("/post/a" => 151)
    expect(in_india.country_gap?).to be_falsy
  end

  it "flags a country filter on a period from before country tracking" do
    early = Period.new({from: "2026-08-01", to: "2026-10-12"}, today: today)

    expect(described_class.new(early, country: "IN").country_gap?).to be_truthy
    expect(described_class.new(early).country_gap?).to be_falsy
    expect(described_class.new(early).country_tracking_since).to eq(Date.new(2026, 10, 1))
  end

  it "finds the first day views and likes were counted, whatever the period" do
    expect(stats.views_counted_since).to eq(Date.new(2026, 9, 1))
    expect(stats.likes_counted_since).to eq(Date.new(2026, 10, 1))
  end

  it "keeps likes from before they were dated aside" do
    expect(stats.undated_likes).to eq(3)
  end

  it "ranks growing countries, new ones first, only above the volume threshold" do
    stub_const("BlogStats::MIN_VIEWS_FOR_GROWTH", 26)

    expect(stats.fastest_growing_countries).to eq([["IN", 151, 0, nil], ["US", 30, 10, 2.0]])
  end

  it "builds a funnel per country with rates only on enough views" do
    india = stats.funnel.find { |row| row.country == "IN" }
    germany = stats.funnel.find { |row| row.country == "DE" }

    expect([india.views, india.likes, india.subscribers, india.messages]).to eq([151, 6, 1, 0])
    expect(india.like_rate).to be_within(0.0001).of(6 / 151.0)
    expect(germany.like_rate).to be_nil
  end

  it "groups weeks from Monday" do
    expect(stats.weekly(:subscribers)).to eq(Date.new(2026, 10, 5) => 2, Date.new(2026, 10, 12) => 0)
  end

  it "ranks pages by how much their views changed" do
    stub_const("BlogStats::MIN_VIEWS_FOR_GROWTH", 5)
    rising, falling = stats.page_changes

    expect(rising.map(&:first)).to eq(%w[/post/a /post/b])
    expect(falling).to eq([])
  end

  it "counts the list's size from everyone who subscribed before the period" do
    expect(stats.subscriber_totals).to eq([1, 2, 2, 3, 3, 3, 3])
  end

  it "joins Google's figures to the funnel by country" do
    india = stats.funnel(search_clicks: {"IN" => 12}).find { |row| row.country == "IN" }

    expect(india.search_clicks).to eq(12)
    expect(india.analytics_views).to be_nil
  end

  it "splits each week's views into the period's top countries and the rest" do
    shares = stats.country_shares(limit: 2)

    expect(shares[:keys]).to eq(%w[IN US])
    expect(shares[:unit]).to eq(:week)
    expect(shares[:buckets]).to eq(Date.new(2026, 10, 5) => {"IN" => 151, "US" => 30, other: 31})
  end

  it "splits a long period by month" do
    long = described_class.new(Period.new({from: "2026-01-01", to: "2026-10-12"}, today: today))

    expect(long.country_shares[:unit]).to eq(:month)
  end

  describe "dated devices and referrers" do
    before do
      PageView.collection.insert_one("_id" => "/post/c", "slug" => "/post/c",
        "devicesByDay" => {"2026-10-07" => {"mobile" => 2}, "2026-10-01" => {"desktop" => 5}},
        "referrersByDay" => {"2026-10-07" => {"google_com" => 2}})
    end

    it "totals them over the period, every country included" do
      expect(stats.devices).to eq("mobile" => 2)
      expect(stats.devices(period.previous)).to eq("desktop" => 5)
      expect(described_class.new(period, country: "IN").referrers).to eq("google_com" => 2)
      expect(stats.breakdowns_tracked_since).to eq(Date.new(2026, 10, 1))
    end

    it "splits each week by its busiest keys, the rest as other" do
      PageView.collection.insert_one("_id" => "/post/d", "slug" => "/post/d",
        "devicesByDay" => {"2026-10-08" => {"desktop" => 4, "tablet" => 1, "mobile" => 1}})

      shares = stats.breakdown_shares(:devices, limit: 2)

      expect(shares[:keys]).to eq(%w[desktop mobile])
      expect(shares[:unit]).to eq(:week)
      expect(shares[:buckets]).to eq(Date.new(2026, 10, 5) => {"desktop" => 4, "mobile" => 3, other: 1})
    end
  end

  describe "unique visitors" do
    before do
      PageViewSeen.collection.insert_many([
        {"slug" => "/post/a", "day" => "2026-10-07", "ipHash" => "one", "country" => "IN"},
        {"slug" => "/post/b", "day" => "2026-10-08", "ipHash" => "one", "country" => "IN"},
        {"slug" => "/post/a", "day" => "2026-10-08", "ipHash" => "two", "country" => "US"},
        {"slug" => "/post/a", "day" => "2026-10-08", "ipHash" => "three"},
        {"slug" => "/post/a", "day" => "2026-10-01", "ipHash" => "four", "country" => "IN"}
      ])
    end

    it "counts a returning reader once over the period" do
      expect(stats.unique_visitors).to eq(3)
      expect(stats.unique_visitors(slug: "/post/b")).to eq(1)
      expect(stats.daily_unique_visitors).to eq([0, 1, 3, 0, 0, 0, 0])
    end

    it "narrows to a country, with markers that have none counted as Unknown" do
      expect(described_class.new(period, country: "IN").unique_visitors).to eq(1)
      expect(described_class.new(period, country: "ZZ").unique_visitors).to eq(1)
    end

    it "knows how far back the kept markers reach" do
      expect(stats.visitors_counted_since).to eq(Date.new(2026, 10, 1))
      expect(stats.visitors_complete?).to be_truthy
      expect(stats.visitors_complete?(period.previous)).to be_falsy
    end
  end

  it "offers every country with a record" do
    expect(stats.countries).to eq(%w[DE IN US ZZ])
  end
end
