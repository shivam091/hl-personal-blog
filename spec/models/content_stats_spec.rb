# encoding: UTF-8

require "rails_helper"

RSpec.describe ContentStats do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: today) }

  def entry(path, type:, published:, updated: published, tags: [])
    FeedEntry.create!(
      url: "https://blog.example.com#{path}",
      name: path.delete_prefix("/post/").humanize,
      type: type,
      published_at: Time.zone.parse(published),
      last_modified_at: Time.zone.parse(updated),
      tags: tags
    )
  end

  before do
    css = Tag.create!(name: "css")
    entry("/post/old", type: "post", published: "2025-01-01", tags: [css])
    entry("/post/new", type: "post", published: "2026-10-08", tags: [css])
    entry("/post/tip", type: "snippet", published: "2026-05-01")

    PageView.collection.insert_many([
      {
        "_id" => "/post/old",
        "slug" => "/post/old",
        "countriesByDay" => {"2026-10-07" => {"IN" => 150}}
      },
      {
        "_id" => "/post/new",
        "slug" => "/post/new",
        "countriesByDay" => {"2026-10-09" => {"IN" => 10}}
      }
    ])

    PageLike.collection.insert_one(
      "_id" => "/post/old",
      "slug" => "/post/old",
      "likeCount" => 3,
      "countriesByDay" => {"2026-10-07" => {"IN" => 3}}
    )

    CrawledPage.create!(
      url: "https://blog.example.com/post/old",
      last_modified_at: Time.zone.parse("2025-01-01"),
      indexed: true
    )
    CrawledPage.create!(
      url: "https://blog.example.com/post/tip",
      last_modified_at: Time.zone.parse("2026-05-01")
    )

    Google::SearchConsole::Stat.create!(
      date: Date.new(2026, 10, 7),
      page: "https://blog.example.com/post/old",
      page_path: "/post/old",
      clicks: 4,
      impressions: 90,
      position: 6.0
    )
  end

  subject(:content) do
    described_class.new(BlogStats.new(period), search: Google::SearchConsole::Summary.new(period))
  end

  it "compares the kinds of content per entry" do
    posts = content.by_type.find { |row| row[:type] == "post" }

    expect(posts).to include(entries: 2, published: 1, views: 160, likes: 3, clicks: 4, average_views: 80.0)
    expect(content.by_type.find { |row| row[:type] == "tutorial" }).to include(entries: 0, average_views: nil)
  end

  it "counts how far entries get from publishing to being liked" do
    expect(content.funnel.to_h).to eq(
      "Published" => 3,
      "In the sitemap" => 2,
      "Indexed" => 1,
      "Shown in search" => 1,
      "Clicked from search" => 1,
      "Read" => 2,
      "Liked" => 1
    )
  end

  it "suggests refreshing stale entries that are still read" do
    expect(content.refresh_candidates(today: today).map(&:path)).to eq(["/post/old"])
  end

  it "adds up tags" do
    expect(content.tags).to eq([
      {tag: "css", entries: 2, views: 160, likes: 3, clicks: 4, average_views: 80.0, like_rate: 3 / 160.0}
    ])
  end

  it "adds up categories, counting an entry in each of its own" do
    guides = Category.create!(name: "Guides")
    web = Category.create!(name: "Web")
    FeedEntry.find("https://blog.example.com/post/old").update!(categories: [guides, web])
    FeedEntry.find("https://blog.example.com/post/new").update!(categories: [web])

    expect(content.categories).to eq([
      {category: "Web", entries: 2, views: 160, likes: 3, clicks: 4, average_views: 80.0, like_rate: 3 / 160.0},
      {category: "Guides", entries: 1, views: 150, likes: 3, clicks: 4, average_views: 150.0, like_rate: 3 / 150.0}
    ])
  end

  it "gives each entry published by the period's end its age then, in months" do
    points = content.decay_points.to_h { |point| [point.item.path, [point.age_months, point.item.views]] }

    expect(points).to eq("/post/old" => [21.3, 150], "/post/new" => [0.1, 10], "/post/tip" => [5.4, 0])
  end

  it "counts entries published per month for a year" do
    months = content.cadence(today: today)

    expect(months.size).to eq(12)
    expect(months.last).to eq([Date.new(2026, 10, 1), {"post" => 1, "tutorial" => 0, "snippet" => 0}])
  end

  it "lays a year of days out in Monday-first weeks up to today" do
    weeks = content.calendar(today: today)

    expect(weeks.size).to eq(53)
    expect(weeks.first.first.date).to eq(Date.new(2025, 10, 13))
    expect(weeks.last.map(&:date)).to eq([today])
    published = weeks.flatten.reject { |day| day.entries.empty? }
    expect(published.map { |day| [day.date, day.entries.map(&:url)] }).to eq([
      [Date.new(2026, 5, 1), ["https://blog.example.com/post/tip"]],
      [Date.new(2026, 10, 8), ["https://blog.example.com/post/new"]]
    ])
  end

  it "bands entries by how long after publishing they were last updated" do
    entry("/post/fixed", type: "post", published: "2026-09-01", updated: "2026-09-04")
    entry("/post/revisited", type: "post", published: "2025-06-01", updated: "2026-03-01")

    updates = content.updates

    expect(updates.bands).to eq("Never" => 3, "Within a week" => 1, "Within a month" => 0, "Within 6 months" => 0, "Later" => 1)
    expect(updates.updated).to eq(2)
    expect(updates.median_days).to eq(138)
    expect(updates.latest.map(&:path)).to eq(["/post/fixed", "/post/revisited"])
  end

  describe "publishing rhythm" do
    before { entry("/post/mid", type: "post", published: "2026-09-30") }

    it "measures the waits between publishing days" do
      expect(content.gaps.map { |gap| [gap.from, gap.to, gap.days] }).to eq([
        [Date.new(2025, 1, 1), Date.new(2026, 5, 1), 485],
        [Date.new(2026, 5, 1), Date.new(2026, 9, 30), 152],
        [Date.new(2026, 9, 30), Date.new(2026, 10, 8), 8]
      ])
    end

    it "sums up the gaps and the weekly streaks" do
      rhythm = content.rhythm(today: today)

      expect(rhythm.since_last).to eq(4)
      expect(rhythm.median_gap).to eq(152)
      expect(rhythm.longest_gap.days).to eq(485)
      expect([rhythm.longest_streak.from, rhythm.longest_streak.weeks]).to eq([Date.new(2026, 9, 28), 2])
      expect(rhythm.current_streak).to eq(2)
    end

    it "ends the current streak once a whole week passes without an entry" do
      expect(content.rhythm(today: Date.new(2026, 10, 18)).current_streak).to eq(2)
      expect(content.rhythm(today: Date.new(2026, 10, 19)).current_streak).to eq(0)
    end
  end

  describe "entries not shown in search" do
    it "lists them oldest first, with the first step each hasn't reached" do
      rows = content.not_in_search

      expect(rows.map(&:path)).to eq(["/post/tip", "/post/new"])
      expect(rows.map(&:search_gap)).to eq(["Not indexed", "Not in the sitemap"])
      expect(rows.map { |item| content.new_entry?(item) }).to eq([false, true])
    end

    it "lists none before Search Console has been synced" do
      Google::SearchConsole::Stat.delete_all

      expect(content.not_in_search).to eq([])
    end
  end

  describe "search readers" do
    before do
      Google::SearchConsole::Stat.create!(
        date: Date.new(2026, 10, 8),
        page: "https://blog.example.com/post/old",
        page_path: "/post/old",
        clicks: 20,
        impressions: 200,
        position: 5.0
      )
      Google::SearchConsole::Stat.create!(
        date: Date.new(2026, 10, 8),
        page: "https://blog.example.com/post/tip",
        page_path: "/post/tip",
        clicks: 12,
        impressions: 100,
        position: 4.0
      )

      organic = {date: Date.new(2026, 10, 8), channel_group: "Organic Search", source: "google", medium: "organic"}

      Google::Analytics::SourceStat.create!(
        page_path: "/post/old",
        sessions: 20,
        engaged_sessions: 4,
        engagement_seconds: 200,
        **organic
      )
      Google::Analytics::SourceStat.create!(
        page_path: "/post/tip",
        sessions: 10,
        engaged_sessions: 9,
        **organic
      )
      # Another channel's readers don't count as search readers.
      Google::Analytics::SourceStat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/old",
        channel_group: "Direct",
        source: "(direct)",
        medium: "(none)",
        sessions: 50,
        engaged_sessions: 50
      )
    end

    it "puts GA's search sessions beside the entry's search clicks" do
      old = content.search_readers.find { |row| row.item.path == "/post/old" }

      expect(old).to have_attributes(
        sessions: 20,
        engagement_rate: 0.2,
        engagement_seconds_per_session: 10.0,
        below_site: true
      )
      expect(old.item.clicks).to eq(24)
    end

    it "picks out entries clicked from search whose readers engage less than the site's search readers" do
      expect(content.site_search_engagement_rate).to eq(13 / 30.0)
      expect(content.search_leaks.map { |row| row.item.path }).to eq(["/post/old"])
    end
  end

  describe "reading" do
    before do
      Google::Analytics::Stat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/old",
        views: 100,
        active_users: 50,
        engagement_seconds: 5000
      )
      Google::Analytics::Stat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/new",
        views: 40,
        active_users: 20,
        engagement_seconds: 400
      )
      # Too few views to judge.
      Google::Analytics::Stat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/tip",
        views: 5,
        active_users: 5,
        engagement_seconds: 50
      )
      Google::Analytics::EventStat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/old",
        event_name: "scroll",
        event_count: 70
      )
      Google::Analytics::EventStat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/new",
        event_name: "scroll",
        event_count: 10
      )
    end

    it "gives each well-read entry's engaged time per reader and read-through, most read first" do
      expect(content.reading.map { |row| [row.item.path, row.views, row.engagement_seconds_per_reader, row.read_through] })
        .to eq([["/post/old", 100, 100.0, 0.7], ["/post/new", 40, 20.0, 0.25]])
    end

    it "measures them against the whole site" do
      expect(content.site_engagement_seconds_per_reader).to eq(5450 / 75.0)
      expect(content.site_read_through).to eq(80 / 145.0)
      expect(content.scrolls?).to be(true)
    end
  end
end
