# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics insights report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  let(:now) { Date.new(2026, 10, 10) }
  let(:before) { Date.new(2026, 9, 10) }

  def ga(model = Google::Analytics::Stat, date: now, **attributes)
    model.create!(date: date, **attributes)
  end

  before do
    # A day older than the period before, so that period reads as synced.
    ga(page_path: "/", date: Date.new(2026, 8, 1))
    ga(page_path: "/post/up", views: 50, sessions: 10, engaged_sessions: 8)
    ga(page_path: "/post/up", views: 10, date: before)
    ga(page_path: "/post/down", views: 5, sessions: 10, engaged_sessions: 8)
    ga(page_path: "/post/down", views: 40, date: before)
    ga(page_path: "/post/dull", views: 30, sessions: 10, engaged_sessions: 1)
    ga(Google::Analytics::EventStat, page_path: "/post/up", event_name: "scroll", event_count: 40)
    ga(Google::Analytics::EventStat, page_path: "/post/dull", event_name: "scroll", event_count: 3)
    ga(Google::Analytics::LandingPageStat, page_path: "/post/dull", sessions: 25, engaged_sessions: 2)
    ga(Google::Analytics::LandingPageStat, page_path: "/post/up", sessions: 25, engaged_sessions: 20)
    ga(Google::Analytics::ReferrerStat, page_path: "/post/up", referrer: "https://www.reddit.com/r/css", views: 6)
    ga(Google::Analytics::ReferrerStat, page_path: "/post/up", referrer: "https://news.ycombinator.com/item", views: 4)
    ga(Google::Analytics::ReferrerStat, page_path: "/post/up", referrer: "https://news.ycombinator.com/", views: 2, date: before)
    ga(Google::Analytics::ReferrerStat, page_path: "/post/up", referrer: "https://harshal-ladhe.vercel.app/", views: 9)
    ga(
      Google::Analytics::SourceStat,
      page_path: "/post/up",
      channel_group: "Organic Search",
      source: "google",
      medium: "organic",
      views: 30,
      sessions: 10,
      engaged_sessions: 5,
      key_events: 2
    )
    ga(
      Google::Analytics::UserAcquisitionStat,
      page_path: "/post/up",
      first_channel_group: "Organic Search",
      first_source: "google",
      first_medium: "organic",
      new_users: 7
    )
    ga(Google::Analytics::TimeOfDayStat, day_of_week: "2", hour: "18", views: 40)
    ga(Google::Analytics::TimeOfDayStat, day_of_week: "5", hour: "08", views: 10)
  end

  it "picks out pages gaining and losing readers, pages and landing pages that don't hold them, and new sites" do
    get analytics_insight_report_path

    expect(response).to have_http_status(:ok)
    cells = ->(id) { page.css("##{id} ~ div table tbody td:first-child").map { |td| td.text.strip } }
    expect(cells.("rising-pages")).to eq(["/post/up", "/post/dull"])
    expect(cells.("falling-pages")).to eq(["/post/down"])
    expect(cells.("unengaging-pages")).to eq(["/post/dull"])
    expect(cells.("read-through")).to eq(["/post/dull", "/post/up"])
    expect(cells.("leaking-landing-pages")).to eq(["/post/dull"])
    expect(cells.("new-sites")).to eq(["reddit.com"])
    expect(cells.("channels")).to eq(["Organic Search"])
    expect(page.at_css("#channels ~ div table tbody tr").text.squish).to include("7")
    expect(page.text.squish).to include("Busiest: Tuesday, around 18:00.")
  end

  it "charts each headline figure on its own tab, against the period before, marking posts published" do
    FeedEntry.create!(url: "https://blog.example.com/post/up", name: "Up", type: "post", published_at: Time.zone.parse("2026-10-10 09:00"),
      last_modified_at: Time.zone.parse("2026-10-10 09:00"))
    # The last day of the period before, so it lines up under the 10th.
    ga(page_path: "/post/up", views: 50, date: Date.new(2026, 9, 30))

    get analytics_insight_report_path(from: "2026-10-01", to: "2026-10-10", trend: "key_events")

    tabs = page.css("[role=tab]")
    expect(tabs.map { |tab| tab.text.strip }).to eq(["Views", "Engagement rate", "Read-through rate", "Key events"])
    expect(tabs.map { |tab| tab["aria-selected"] }).to eq(%w[false false false true])
    expect(page.css("[role=tabpanel]").reject { |panel| panel.key?("hidden") }.map { |panel| panel["id"] }).to eq(["trend-panel-key_events"])

    day = page.css("#trend-panel-views rect[data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }.find { |tip| tip["rows"].any? { |row| row["name"] == "Up" } }
    expect(day["rows"].map { |row| row["value"] }).to eq(["85", "50", "Published"])
    expect(day["rows"][1]["change"]).to eq("(+70%)")
    expect(day["rows"].last["name"]).to eq("Up")
  end

  it "sets pages, landing pages and content types against the period before, and shows no changes with No comparison" do
    ga(Google::Analytics::ContentGroupStat, page_path: "/post/up", content_group: "tutorial", content_category: "css", content_tags: "css", views: 50)

    get analytics_insight_report_path

    expect(page.at_css("#unengaging-pages ~ div tbody tr").text.squish).to include("/post/dull 30 (new)")
    expect(page.at_css("#leaking-landing-pages ~ div tbody tr").text.squish).to include("25 (new)")
    expect(page.at_css("#read-through ~ div tbody tr").text.squish).to include("30 (new)")

    get analytics_insight_report_path(compare: "off")

    expect(page.at_css("#unengaging-pages ~ div tbody tr").text.squish).not_to include("(")
    expect(page.at_css("#leaking-landing-pages ~ div tbody tr").text.squish).not_to include("(new)")
    expect(page.at_css("#rising-pages").parent.text).to include("Pick a comparison in the Compare menu")
    expect(page.at_css("#new-sites").parent.text).to include("Pick a comparison in the Compare menu")
  end

  it "plots each tested page's phone load time against its engagement" do
    Google::PageSpeed::Result.create!(url: "https://blog.example.com/post/up", page_path: "/post/up", strategy: "mobile",
      lab_lcp_ms: 4500, performance: 0.4)

    get analytics_insight_report_path

    dot = JSON.parse(page.at_css("#speed-engagement ~ div span[data-tip]")["data-tip"])
    expect(dot["title"]).to eq("/post/up")
    expect(dot["rows"].map { |row| row["value"] }).to eq(["4.5 s", "80%", "50"])
  end

  it "plots readers' own load time once they've reported enough, saying so" do
    ga(Google::Analytics::WebVitalStat, page_path: "/post/up", metric: "LCP", rating: "poor", event_count: 10, value_sum: 45_000)

    get analytics_insight_report_path

    dot = JSON.parse(page.at_css("#speed-engagement ~ div span[data-tip]")["data-tip"])
    expect(dot["rows"].first).to include("value" => "4.5 s", "name" => "readers' mean LCP")
    expect(page.at_css("#speed-engagement ~ p").text.squish).to include("Web Vitals reports: readers' mean load time")
  end

  it "compares content types by their pages' own engagement and finished reads" do
    ga(Google::Analytics::ContentGroupStat, page_path: "/post/up", content_group: "tutorial", content_category: "css", content_tags: "css", views: 50)
    ga(Google::Analytics::ArticleReadStat, page_path: "/post/up", reads: 20, read_seconds: 2400)

    get analytics_insight_report_path

    expect(page.css("#content-groups ~ div tbody tr").map { |row| row.text.squish }.first).to eq("tutorial 1 50 (new) 80% 0s 40.0%")
    expect(page.css("#categories ~ div tbody td:first-child").map { |cell| cell.text.strip }).to eq(["css", "(not set)"])
  end

  it "ranks outbound links with their safety, and the pages readers leave from" do
    ga(Google::Analytics::OutboundLinkStat, page_path: "/post/up", link_url: "https://bad.example.com/", event_count: 5)
    Google::SafeBrowsing::LinkCheck.create!(url: "https://bad.example.com/", threat_types: ["SOCIAL_ENGINEERING"])

    get analytics_insight_report_path

    expect(page.css("#outbound-links ~ div table").last.css("tbody td").map { |cell| cell.text.strip }).to eq(["https://bad.example.com/", "5", "1", "Flagged"])
    expect(page.css("#outbound-pages ~ div tbody tr td").map { |cell| cell.text.strip }).to eq(["/post/up", "5", "50", "10%"])
  end

  it "says which figures follow the country filter" do
    ga(Google::Analytics::CountryStat, page_path: "/post/up", country: "IN", views: 3)

    get analytics_insight_report_path(country: "IN")

    expect(Nokogiri::HTML5(response.body).text.squish).to include("GA doesn't split scrolls, landing pages or sources by country")
  end

  it "exports each list as CSV" do
    get analytics_insight_report_path(format: :csv, export: "read-through")

    expect(CSV.parse(response.body)).to eq([
      ["Page", "Views", "Scrolls", "Finished reads", "Read-through rate", "Reading time per read (s)"],
      ["/post/dull", "30", "3", "0", "0.1", nil],
      ["/post/up", "50", "40", "0", "0.8", nil]])

    get analytics_insight_report_path(format: :csv, export: "channels")

    expect(CSV.parse(response.body)).to eq([
      ["Channel", "Views", "New users", "Engagement rate", "Key events"],
      ["Organic Search", "30 (new)", "7", "0.5", "2"]
    ])

    get analytics_insight_report_path(format: :csv, export: "sites")

    expect(CSV.parse(response.body)).to eq([["Site", "Views"], ["reddit.com", "6 (new)"],
      ["news.ycombinator.com", "4 (+100%)"]])
  end

  it "shows an empty state before the first sync" do
    Google::Analytics::Stat.delete_all

    get analytics_insight_report_path

    expect(response.body).to include("No Analytics figures yet.")
  end
end
