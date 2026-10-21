# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::Insights do
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-11"}, today: Date.new(2026, 10, 12)) }

  subject(:insights) { described_class.new(period) }

  def page(path, views:, engaged:, lcp_ms:)
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: path, views: views, sessions: 10, engaged_sessions: engaged)
    Google::PageSpeed::Result.create!(url: "https://blog.example.com#{path}", page_path: path, strategy: "mobile", lab_lcp_ms: lcp_ms,
      performance: 0.5)
  end

  describe "outbound links" do
    def click(path, url, count)
      Google::Analytics::OutboundLinkStat.create!(date: Date.new(2026, 10, 10), page_path: path, link_url: url, event_count: count)
    end

    before do
      click("/post/a", "https://developer.mozilla.org/en-US/docs/Web/CSS/grid", 6)
      click("/post/b", "https://developer.mozilla.org/en-US/docs/Web/CSS/grid", 2)
      click("/post/b", "https://bad.example.com/", 3)
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/b", views: 50)
      Google::SafeBrowsing::LinkCheck.create!(url: "https://bad.example.com/", threat_types: ["MALWARE"])
    end

    it "ranks links by clicks with the pages they were clicked from and their safety" do
      expect(insights.outbound_links.map { |row| [row.url, row.clicks, row.pages, row.check&.flagged?] }).to eq([
        ["https://developer.mozilla.org/en-US/docs/Web/CSS/grid", 8, 2, nil],
        ["https://bad.example.com/", 3, 1, true]
      ])
    end

    it "sums clicks by site and by the page they left from" do
      expect(insights.outbound_sites).to eq("developer.mozilla.org" => 8, "bad.example.com" => 3)
      expect(insights.outbound_pages.map { |row| [row.page_path, row.clicks, row.views, row.rate] }).to eq([
        ["/post/a", 6, 0, nil], ["/post/b", 5, 50, 0.1]
      ])
    end
  end

  describe "speed against engagement" do
    it "joins each well-read page's phone LCP to its engagement rate" do
      page("/post/fast", views: 40, engaged: 9, lcp_ms: 1200)
      page("/post/rare", views: 5, engaged: 9, lcp_ms: 1200)
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/untested", views: 40, sessions: 10, engaged_sessions: 5)

      points = insights.speed_points

      expect(points.map { |point| [point.page_path, point.lcp_ms, point.engagement_rate] }).to eq([["/post/fast", 1200.0, 0.9]])
    end

    it "prefers readers' mean LCP from enough reports, keeping the lab run as the alternative" do
      page("/post/fast", views: 40, engaged: 9, lcp_ms: 1200)
      page("/post/slow", views: 40, engaged: 3, lcp_ms: 1500)
      Google::Analytics::WebVitalStat.create!(date: Date.new(2026, 10, 10), page_path: "/post/slow", metric: "LCP", rating: "poor",
        event_count: 10, value_sum: 50_000)
      Google::Analytics::WebVitalStat.create!(date: Date.new(2026, 10, 10), page_path: "/post/fast", metric: "LCP", rating: "good",
        event_count: 9, value_sum: 9000)

      expect(insights.speed_source).to eq(:readers)
      expect(insights.speed_points.map { |point| [point.page_path, point.lcp_ms, point.source] }).to eq([["/post/slow", 5000.0, :readers]])
      expect(insights.speed_points(source: :lab).map(&:page_path)).to contain_exactly("/post/fast", "/post/slow")
    end

    it "falls back to the lab run while readers have reported nothing" do
      page("/post/fast", views: 40, engaged: 9, lcp_ms: 1200)

      expect(insights.speed_source).to eq(:lab)
      expect(insights.speed_points.sole.source).to eq(:lab)
    end

    it "correlates load time with engagement once enough pages have both" do
      {"/a" => [1000, 9], "/b" => [2000, 8], "/c" => [3000, 6], "/d" => [4000, 5]}.each do |path, (lcp_ms, engaged)|
        page(path, views: 30, engaged: engaged, lcp_ms: lcp_ms)
      end
      expect(insights.speed_correlation).to be_nil

      page("/e", views: 30, engaged: 3, lcp_ms: 5000)
      expect(described_class.new(period).speed_correlation).to be_within(0.01).of(-0.99)
    end
  end

  describe "read-through" do
    def views(path, count)
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 5), page_path: path, views: count, sessions: count, engaged_sessions: count / 2)
    end

    def scroll(path, date, count)
      Google::Analytics::EventStat.create!(date: date, page_path: path, event_name: "scroll", event_count: count)
    end

    it "counts GA's scrolls while the blog has sent no finished reads" do
      views("/post/a", 40)
      scroll("/post/a", Date.new(2026, 10, 5), 10)

      expect(insights.reads_since).to be_nil
      expect(insights.read_through.sole).to have_attributes(scrolls: 10, reads: 0, rate: 0.25)
    end

    it "counts finished reads from their first day, and scrolls only before it" do
      views("/post/a", 40)
      scroll("/post/a", Date.new(2026, 10, 3), 6)
      scroll("/post/a", Date.new(2026, 10, 8), 30)
      Google::Analytics::ArticleReadStat.create!(date: Date.new(2026, 10, 6), page_path: "/post/a", reads: 4, read_seconds: 480)

      row = insights.read_through.sole
      expect(insights.reads_since).to eq(Date.new(2026, 10, 6))
      expect(row).to have_attributes(scrolls: 6, reads: 4, completions: 10, rate: 0.25, seconds_per_read: 120.0)
      expect(insights.to_csv("read-through").lines.last.chomp).to eq("/post/a,40,6,4,0.25,120.0")
    end
  end

  describe "content groups" do
    def viewed(path, group, category, tags, views:, engaged:, reads: 0)
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 5), page_path: path, views: views, sessions: views, engaged_sessions: engaged,
        engagement_seconds: views * 30.0)
      Google::Analytics::ContentGroupStat.create!(date: Date.new(2026, 10, 5), page_path: path, content_group: group, content_category: category,
        content_tags: tags, views: views)
      Google::Analytics::ArticleReadStat.create!(date: Date.new(2026, 10, 5), page_path: path, reads: reads, read_seconds: reads * 60) if reads.positive?
    end

    before do
      viewed("/post/a", "post", "css", "css,grid", views: 40, engaged: 20, reads: 10)
      viewed("/tutorial/b", "tutorial", "css", "css", views: 20, engaged: 15, reads: 8)
      viewed("/snippet/c", "snippet", "js", "js", views: 10, engaged: 2)
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 5), page_path: "/old", views: 5, sessions: 5, engaged_sessions: 1)
    end

    it "joins each type's pages to their own engagement and finished reads" do
      expect(insights.content_groups.map { |row| [row.name, row.pages, row.views, row.engagement_rate, row.reads, row.read_rate] }).to eq([
        ["post", 1, 40, 0.5, 10, 0.25], ["tutorial", 1, 20, 0.75, 8, 0.4], ["snippet", 1, 10, 0.2, 0, 0.0], ["(not set)", 1, 5, 0.2, 0, 0.0]
      ])
      expect(insights.content_groups(:content_category).map { |row| [row.name, row.views] }).to eq([["css", 60], ["js", 10], ["(not set)", 5]])
    end

    it "counts a page under each of its tags" do
      expect(insights.content_groups(:content_tags).map { |row| [row.name, row.views] }).to eq([["css", 60], ["grid", 40], ["js", 10], ["(not set)", 5]])
      expect(insights.to_csv("tags").lines.second.chomp).to eq("css,2,60,0.5833,30.0,18,0.3,60.0")
    end
  end
end
