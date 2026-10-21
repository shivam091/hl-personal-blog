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

    it "correlates load time with engagement once enough pages have both" do
      {"/a" => [1000, 9], "/b" => [2000, 8], "/c" => [3000, 6], "/d" => [4000, 5]}.each do |path, (lcp_ms, engaged)|
        page(path, views: 30, engaged: engaged, lcp_ms: lcp_ms)
      end
      expect(insights.speed_correlation).to be_nil

      page("/e", views: 30, engaged: 3, lcp_ms: 5000)
      expect(described_class.new(period).speed_correlation).to be_within(0.01).of(-0.99)
    end
  end
end
