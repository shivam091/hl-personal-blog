# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics engagement", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  before do
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "scroll", event_count: 5, total_users: 3, active_users: 2)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/b", event_name: "scroll", event_count: 3, total_users: 2, active_users: 1)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "click", event_count: 1, total_users: 1, active_users: 1, key_events: 1)
  end

  def table_rows
    Nokogiri::HTML5(response.body).css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.drop(1) }
  end

  def ticked_rows
    page.css("tbody tr").map { |row| row.at_css("input[type=checkbox]").key?("checked") }
  end

  # Read from the readout, since the bars themselves show only names.
  def bar_readouts
    page.css("#chart-ranking ~ div li").map do |bar|
      tip = JSON.parse(bar["data-tip"])
      [bar.text.squish, tip["rows"].first["value"], tip["rows"].first["name"]]
    end
  end

  def legend
    page.css("[aria-labelledby='chart-over-time'] li").map { |entry| entry.text.squish }
  end

  def page
    Nokogiri::HTML5(response.body)
  end

  it "shows the events breakdown at the bare path" do
    get google_analytics_engagement_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("nav[aria-label=Breakdown] a[aria-current=page]").text).to eq("Events")
  end

  it "totals each event across pages, each as a share of the total" do
    get google_analytics_engagement_breakdown_path("events")

    expect(table_rows).to eq([["1", "scroll", "8 (88.89%)", "5 (83.33%)", "3 (75%)", "2.67", "—", "0"],
      ["2", "click", "1 (11.11%)", "1 (16.67%)", "1 (25%)", "1.00", "—", "1"]])
    expect(page.css("thead tr").last.css("th, td").map { |cell| cell.text.squish })
      .to eq(["", "", "Total", "9 100% of total", "6 100% of total", "4 100% of total", "2.25", "—", "1"])
  end

  it "charts the leading events over time and by their share" do
    get google_analytics_engagement_breakdown_path("events")

    expect(page.css("section h2").map { |title| title.text.squish })
      .to include("Event count by event over time", "Event count by event")
    expect(legend).to eq(%w[Total scroll click])
    expect(ticked_rows).to eq([true, true])
    expect(bar_readouts).to eq([["scroll", "8", "88.89% of total"], ["click", "1", "11.11% of total"]])
  end

  it "picks a line out from its legend entry, its bar answering to the same series" do
    get google_analytics_engagement_breakdown_path("events")

    expect(page.css("[aria-labelledby='chart-over-time'] li button").map { |toggle| [toggle.text.squish, toggle["data-series"], toggle["aria-pressed"]] })
      .to eq([%w[Total 0 false], %w[scroll 1 false], %w[click 2 false]])
    expect(page.css("#chart-ranking ~ div li").map { |bar| bar["data-series"] }).to eq(%w[1 2])
  end

  it "charts only the rows ticked, kept in every link" do
    get google_analytics_engagement_breakdown_path("events", plot: [["click"]].to_json)

    expect(legend).to eq(%w[Total click])
    expect(ticked_rows).to eq([false, true])
    expect(page.at_css("thead a[href*='sort=']")["href"]).to include("plot=")
  end

  it "charts a week or a month at a time, summed, keeping the choice in every link" do
    Google::Analytics::EventStat.create!(date: Date.new(2026, 9, 30), page_path: "/post/a", event_name: "scroll", event_count: 4, active_users: 1)

    get google_analytics_engagement_breakdown_path("events", chart_by: "month", from: "2026-09-01", to: "2026-10-12")

    tips = page.css("[aria-labelledby='chart-over-time'] rect[data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }
    expect(tips.map { |tip| [tip["title"], tip["rows"].map { |row| row["value"] }] })
      .to eq([["September 2026", %w[4 4 0]], ["October 2026", %w[9 8 1]]])
    expect(page.at_css("select#chart-by option[selected]")["value"]).to eq("month")
    expect(page.at_css("thead a[href*='sort=']")["href"]).to include("chart_by=month")

    get google_analytics_engagement_breakdown_path("events", chart_by: "week", from: "2026-09-15", to: "2026-10-12")

    titles = page.css("[aria-labelledby='chart-over-time'] rect[data-tip]").map { |hit| JSON.parse(hit["data-tip"])["title"] }
    expect(titles.first(2)).to eq(["Week of 13 Sep, 2026", "Week of 20 Sep, 2026"])
    expect(titles.size).to eq(5)
  end

  it "leaves Total out once unticked, and charts nothing with no rows ticked" do
    get google_analytics_engagement_breakdown_path("events", plot: "[]", plot_total: "0")

    expect(page.css("[aria-labelledby='chart-over-time'] p, #chart-ranking ~ div p").map(&:text).uniq).to eq(["Tick rows in the table to chart them."])
    expect(ticked_rows).to eq([false, false])
  end

  it "falls back to the leading rows when the rows asked for aren't readable" do
    get google_analytics_engagement_breakdown_path("events", plot: "not json")

    expect(legend).to eq(%w[Total scroll click])
  end

  it "splits each event by page, narrowed to a page searched" do
    get google_analytics_engagement_breakdown_path("pages", path: "/post/a")

    expect(table_rows).to eq([["1", "scroll", "/post/a", "5 (83.33%)", "3 (75%)", "2 (66.67%)", "2.50", "—", "0"],
      ["2", "click", "/post/a", "1 (16.67%)", "1 (25%)", "1 (33.33%)", "1.00", "—", "1"]])
    expect(bar_readouts).to eq([["scroll · /post/a", "5", "83.33% of total"], ["click · /post/a", "1", "16.67% of total"]])
  end

  it "offers each tab's splits under its column, with events by page among the events' rather than a tab" do
    # A row in each, since the column, and its menu, only show with rows.
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 1)
    Google::Analytics::PageTitleStat.create!(date: yesterday, page_path: "/post/a", page_title: "A", views: 1)
    Google::Analytics::OutboundLinkStat.create!(date: yesterday, page_path: "/post/a", link_url: "https://github.com/x", event_count: 1)
    Google::Analytics::EventLabelStat.create!(date: yesterday, page_path: "/post/a", event_name: "share", event_label: "x", event_count: 1)
    Google::Analytics::EventMethodStat.create!(date: yesterday, page_path: "/post/a", event_name: "cover_image_open", event_method: "click", event_count: 1)
    Google::Analytics::LandingPageStat.create!(date: yesterday, page_path: "/post/a", sessions: 1)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")
    {
      "events" => ["By page"], "key-events" => ["By page"],
      "pages-and-screens" => ["By event"], "page-titles" => ["By page path"], "outbound-links" => ["By page"], "event-labels" => ["By page"],
      "event-methods" => ["By page"], "landing-pages" => ["By source"]
    }.each do |tab, splits|
      get google_analytics_engagement_breakdown_path(tab)

      expect(page.css("thead select#breakdown-split option").map(&:text)).to eq(["No split", *splits]), tab
    end
    get google_analytics_engagement_breakdown_path("scroll-depth")
    expect(page.at_css("thead select#breakdown-split")).to be_nil
    expect(page.css("nav[aria-label=Breakdown] a").map { |tab| tab.text.squish }).to eq(
      ["Events", "Key events", "Pages and screens", "Page titles", "Outbound links", "Event labels", "Event methods", "Landing page", "Scroll depth",
       "Internal navigation", "Missing pages"]
    )

    get google_analytics_engagement_breakdown_path("pages")
    expect(page.at_css("nav[aria-label=Breakdown] a[aria-current=page]").text.squish).to eq("Events")
    expect(page.at_css("thead select#breakdown-split option[selected]").text).to eq("By page")
  end

  it "splits a page title by the paths that sent it" do
    Google::Analytics::PageTitleStat.create!(date: yesterday, page_path: "/", page_title: "Harshal V. LADHE", views: 5)
    Google::Analytics::PageTitleStat.create!(date: yesterday, page_path: "/tutorial/a", page_title: "Harshal V. LADHE", views: 2)

    get google_analytics_engagement_breakdown_path("page-title-paths")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "Harshal V. LADHE", "/", "5 (71.43%)"], ["2", "Harshal V. LADHE", "/tutorial/a", "2 (28.57%)"]])
  end

  it "takes users from GA for the period, so a reader seen on several days and pages counts once" do
    allow(Google::Analytics::LiveFigures).to receive(:call) { Google::Analytics::LiveFigures::Result.new(
      rows: {%w[scroll] => {total_users: 2, active_users: 1, sessions: 4}, %w[click] => {total_users: 1, active_users: 1, sessions: 1}},
      total: {total_users: 2, active_users: 1, sessions: 5}
    ) }

    get google_analytics_engagement_breakdown_path("events", path: "/post/")

    expect(table_rows).to eq([["1", "scroll", "8 (88.89%)", "2 (100%)", "1 (100%)", "8.00", "2.00", "0"],
      ["2", "click", "1 (11.11%)", "1 (50%)", "1 (100%)", "1.00", "1.00", "1"]])
    expect(page.css("thead tr").last.css("td").map { |cell| cell.text.squish }.last(4)).to eq(["1 100% of total", "9.00", "1.80", "1"])
    expect(Google::Analytics::LiveFigures).to have_received(:call).with(hash_including(
      dimensions: {event_name: "eventName"}, metrics: {total_users: "totalUsers", active_users: "activeUsers", sessions: "sessions"},
      filters: [["pagePath", "CONTAINS", "/post/"]]
    )).at_least(:once)
  end

  it "lists landing pages with GA's own sessions and users, charted by sessions" do
    Google::Analytics::LandingPageStat.create!(date: yesterday, page_path: "/post/a", sessions: 3, engagement_seconds: 100.0, key_events: 1)
    Google::Analytics::LandingPageStat.create!(date: yesterday - 1, page_path: "/post/a", sessions: 2, engagement_seconds: 50.0)
    Google::Analytics::LandingPageStat.create!(date: yesterday, page_path: "/", sessions: 15, engagement_seconds: 300.0)
    allow(Google::Analytics::LiveFigures).to receive(:call) { Google::Analytics::LiveFigures::Result.new(
      rows: {%w[/post/a] => {sessions: 5, active_users: 4, new_users: 2}, %w[/] => {sessions: 15, active_users: 10, new_users: 8}},
      total: {sessions: 20, active_users: 13, new_users: 10}
    ) }

    get google_analytics_engagement_breakdown_path("landing-pages")

    expect(page.css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }.drop(2))
      .to eq(["Landing page", "Sessions", "Active users", "New users", "Average engagement time per session", "Key events"])
    expect(table_rows).to eq([["1", "/", "15 (75%)", "10 (76.92%)", "8 (80%)", "20s", "0"],
      ["2", "/post/a", "5 (25%)", "4 (30.77%)", "2 (20%)", "30s", "1"]])
    expect(page.css("section h2").map { |title| title.text.squish }).to include("Sessions by landing page over time")
    expect(Google::Analytics::LiveFigures).to have_received(:call).with(hash_including(
      dimensions: {page_path: "landingPage"}, metrics: {sessions: "sessions", active_users: "activeUsers", new_users: "newUsers"}
    )).at_least(:once)
  end

  it "splits landing pages by the source each session came from" do
    Google::Analytics::LandingSourceStat.create!(date: yesterday, page_path: "/post/a", channel_group: "Organic Search", source: "google",
      medium: "organic", sessions: 4)
    Google::Analytics::LandingSourceStat.create!(date: yesterday, page_path: "/", channel_group: "Direct", source: "(direct)", medium: "(none)", sessions: 1)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("landing-page-sources", source: "goo")

    expect(table_rows.map { |row| row.first(6) }).to eq([["1", "/post/a", "Organic Search", "google", "organic", "4 (100%)"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call).with(hash_including(
      dimensions: {page_path: "landingPage", channel_group: "sessionDefaultChannelGroup", source: "sessionSource", medium: "sessionMedium"},
      filters: [["sessionSource", "CONTAINS", "goo"]]
    )).at_least(:once)
  end

  it "reads each page's scrolls against its views, without the page's other events" do
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 10, active_users: 4, event_count: 40)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/b", views: 4, active_users: 2, event_count: 9)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("scroll-depth", sort: "scroll_rate", direction: "desc")

    expect(page.css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }.drop(2))
      .to eq(["Page path", "Views", "Active users", "Scrolls", "Scrolled to the end", "Average engagement time per active user"])
    expect(table_rows.map { |row| [row[1], row[4], row[5]] }).to eq([["/post/b", "3 (37.5%)", "75%"], ["/post/a", "5 (62.5%)", "50%"]])
  end

  it "lists moves between the blog's own pages, leaving outside referrers to Acquisition" do
    own = "https://#{Blog.host}/post/a"
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/post/b", referrer: own, views: 3)
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/post/b", referrer: "https://news.ycombinator.com/", views: 9)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("internal-navigation")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", own, "/post/b", "3 (100%)"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(filters: [["pageReferrer", "CONTAINS", "//#{Blog.host}"]])).at_least(:once)
  end

  it "lists what linked to the pages readers found missing, asking GA for those pages alone" do
    Google::Analytics::EventStat.create!(date: yesterday - 30, page_path: "/old-post", event_name: "page_not_found", event_count: 1)
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/old-post", referrer: "https://dev.to/x", views: 2)
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/post/a", referrer: "https://dev.to/x", views: 7)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("missing-pages")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "/old-post", "https://dev.to/x", "2 (100%)"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(filters: [["pagePath", "FULL_REGEXP", "/old\\-post"]])).at_least(:once)
  end

  it "asks GA for no page at all while no page has been missing" do
    expect(Google::Analytics::EngagementController.missing_page_filters).to eq([["pagePath", "EXACT", "(not set)"]])
  end

  it "lists events by the method they carry" do
    Google::Analytics::EventMethodStat.create!(date: yesterday, page_path: "/post/a", event_name: "cover_image_open", event_method: "new_tab", event_count: 2)
    Google::Analytics::EventMethodStat.create!(date: yesterday, page_path: "/post/b", event_name: "cover_image_open", event_method: "click", event_count: 6)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("event-methods")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "cover_image_open", "click", "6 (75%)"], ["2", "cover_image_open", "new_tab", "2 (25%)"]])
  end

  it "shows each row's key events against the same row in the period before" do
    before = yesterday - 13
    Google::Analytics::EventStat.create!(date: before, page_path: "/post/a", event_name: "click", event_count: 4, key_events: 4)
    Google::Analytics::EventStat.create!(date: before, page_path: "/post/c", event_name: "submit", event_count: 2, key_events: 2)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/c", event_name: "submit", event_count: 3, key_events: 3)

    get google_analytics_engagement_breakdown_path("events", from: (yesterday - 6).iso8601, to: yesterday.iso8601, compare: "off")
    expect(table_rows.map { |row| [row[1], row.last] }).to eq([["scroll", "0"], ["submit", "3"], ["click", "1"]])

    get google_analytics_engagement_breakdown_path("events", from: (yesterday - 6).iso8601, to: yesterday.iso8601)
    expect(table_rows.map { |row| [row[1], row.last] }).to eq([["scroll", "0 (–)"], ["submit", "3 (+50%)"], ["click", "1 (−75%)"]])
    expect(page.css("thead tr").last.css("td").last.text.squish).to eq("4 (−33.3%)")
  end

  it "shows every column's change once a comparison is picked, and shares without one" do
    before = yesterday - 13
    Google::Analytics::EventStat.create!(date: before, page_path: "/post/a", event_name: "click", event_count: 4, key_events: 4)
    Google::Analytics::EventStat.create!(date: before, page_path: "/post/c", event_name: "submit", event_count: 2, key_events: 2)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/c", event_name: "submit", event_count: 3, key_events: 3)

    get google_analytics_engagement_breakdown_path("events", from: (yesterday - 6).iso8601, to: yesterday.iso8601, sort: "event_name", compare: "off")
    expect(table_rows.map { |row| row.values_at(1, 2) }).to eq([["click", "1 (8.33%)"], ["scroll", "8 (66.67%)"], ["submit", "3 (25%)"]])
    expect(page.css("thead tr").last.css("td")[2].text.squish).to eq("12 100% of total")

    get google_analytics_engagement_breakdown_path("events", from: (yesterday - 6).iso8601, to: yesterday.iso8601, sort: "event_name")
    expect(table_rows.map { |row| row.values_at(1, 2) }).to eq([["click", "1 (−75%)"], ["scroll", "8 (new)"], ["submit", "3 (+50%)"]])
    expect(page.css("thead tr").last.css("td")[2].text.squish).to eq("12 (+100%)")
  end

  it "lists pages with every event on each added up, beside its views and GA's own users" do
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/", views: 10, active_users: 3, engagement_seconds: 120.0)
    Google::Analytics::Stat.create!(date: yesterday - 1, page_path: "/", views: 5, active_users: 2, engagement_seconds: 30.0)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 4, active_users: 2, engagement_seconds: 50.0, key_events: 1)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/", event_name: "page_view", event_count: 15)
    allow(Google::Analytics::LiveFigures).to receive(:call) { Google::Analytics::LiveFigures::Result.new(
      rows: {%w[/] => {active_users: 4}, %w[/post/a] => {active_users: 2}}, total: {active_users: 5}
    ) }

    get google_analytics_engagement_breakdown_path("pages-and-screens", sort: "event_count", direction: "desc")

    pp page.css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }.drop(2), table_rows, page.css("thead tr").last.css("td").map { |cell| cell.text.squish }.drop(2)
    expect(page.css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }.drop(2)).to eq(["Page path", "Views", "Active users",
      "Views per active user", "New users", "Sessions", "Engaged sessions", "Engagement rate", "Engaged sessions per active user",
      "Average engagement time per active user", "Events per session", "Event count", "Key events"])
    expect(table_rows.map { |row| row.values_at(0, 1, 2, 3, 4, 10, 12, 13) }).to eq([["1", "/", "15 (78.95%)", "4 (80%)", "3.75", "38s", "15 (62.5%)", "0"],
      ["2", "/post/a", "4 (21.05%)", "2 (40%)", "2.00", "25s", "6 (25%)", "1"]])
    expect(page.css("thead tr").last.css("td").map { |cell| cell.text.squish }.drop(2).values_at(0, 1, 2, 8, 10, 11))
      .to eq(["19 100% of total", "5 100% of total", "3.80", "40s", "24 100% of total", "1"])
    expect(page.css("section h2").map { |title| title.text.squish }).to include("Views by page path over time")

    get google_analytics_engagement_breakdown_path("pages-and-screens", path: "/post/")

    expect(table_rows.map { |row| [row[1], row[12]] }).to eq([["/post/a", "6 (66.67%)"]])
  end

  it "totals each page, working out engagement, views per user and events per session from the summed counts" do
    traffic = {views: 10, active_users: 4, new_users: 2, sessions: 5, engaged_sessions: 2, engagement_seconds: 200.0, event_count: 7, key_events: 1}
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", **traffic)
    Google::Analytics::Stat.create!(date: yesterday - 1, page_path: "/post/a", **traffic, engaged_sessions: 3)

    get google_analytics_engagement_breakdown_path("pages-and-screens")

    expect(table_rows).to eq([["1", "/post/a", "20 (100%)", "8 (100%)", "2.50", "4 (100%)", "10 (100%)", "5 (100%)", "50%", "0.63", "50s", "0.60",
      "6 (66.67%)", "2"]])
    expect(Nokogiri::HTML5(response.body).at_css("th[title^='The number of distinct users']").text.squish).to eq("Active users")
    expect(Nokogiri::HTML5(response.body).text.squish).to include("Couldn't get users and sessions from Google Analytics (not asked in specs)")
  end


  it "takes users and sessions from GA for the period, since stored days and pages can't be added up into them" do
    traffic = {views: 10, active_users: 4, new_users: 2, sessions: 5, engaged_sessions: 2, engagement_seconds: 200.0, key_events: 1}
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", **traffic)
    Google::Analytics::Stat.create!(date: yesterday - 1, page_path: "/post/a", **traffic)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/b", **traffic, views: 30)
    live = {active_users: 5, new_users: 1, sessions: 6, engaged_sessions: 3}
    allow(Google::Analytics::LiveFigures).to receive(:call) { Google::Analytics::LiveFigures::Result.new(
      rows: {%w[/post/a] => live, %w[/post/b] => {active_users: 3, new_users: 3, sessions: 4, engaged_sessions: 1}},
      total: {active_users: 7, new_users: 4, sessions: 9, engaged_sessions: 4}
    ) }

    get google_analytics_engagement_breakdown_path("pages-and-screens", sort: "active_users", direction: "desc")

    expect(table_rows).to eq([["1", "/post/a", "20 (40%)", "5 (71.43%)", "4.00", "1 (25%)", "6 (66.67%)", "3 (75%)", "50%", "0.60", "1m 20s", "1.00", "6 (66.67%)", "2"],
      ["2", "/post/b", "30 (60%)", "3 (42.86%)", "10.00", "3 (75%)", "4 (44.44%)", "1 (25%)", "25%", "0.33", "1m 07s", "0.75", "3 (33.33%)", "1"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(dimensions: {page_path: "pagePath"}, metrics: Google::Analytics::AcquisitionController::LIVE_METRICS))
    expect(Nokogiri::HTML5(response.body).text).not_to include("Couldn't get users")
  end


  it "shows each row's key events against the period before, as GA does, rather than as a share" do
    Google::Analytics::Stat.create!(date: yesterday - 60, page_path: "/post/a", views: 1, key_events: 2)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 3, key_events: 3)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/b", views: 2, key_events: 1)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/c", views: 1)

    get google_analytics_engagement_breakdown_path("pages-and-screens", from: (yesterday - 27).iso8601, to: yesterday.iso8601, compare: "previous")

    expect(table_rows.map { |row| [row[1], row.last] }).to eq([["/post/a", "3 (new)"], ["/post/b", "1 (new)"], ["/post/c", "0 (–)"]])
  end


  it "narrows Event count to the event chosen in its column head, asking GA for that event's figures" do
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 3, sessions: 2, event_count: 9, key_events: 1)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/b", views: 1, sessions: 1, event_count: 4)
    # A day earlier, since the before block already holds yesterday's scroll for /post/a.
    Google::Analytics::EventStat.create!(date: yesterday - 1, page_path: "/post/a", event_name: "scroll", event_count: 2)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "sign_up", event_count: 1, key_events: 1)
    allow(Google::Analytics::LiveFigures).to receive(:call) do |metrics:, **|
      raise Google::Analytics::LiveFigures::Unavailable, "not asked in specs" unless metrics == {event_count: "eventCount"}

      Google::Analytics::LiveFigures::Result.new(rows: {%w[/post/a] => {event_count: 2}}, total: {event_count: 2})
    end

    get google_analytics_engagement_breakdown_path("pages-and-screens", event: "scroll")

    page = Nokogiri::HTML5(response.body)
    expect(table_rows.map { |row| [row[1], *row.last(3)] }).to eq([["/post/a", "4.50", "2 (100%)", "1"], ["/post/b", "3.00", "0 (0%)", "0"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(dimensions: {page_path: "pagePath"}, filters: [["eventName", "EXACT", "scroll"]]))
    expect(page.css("#event-filter-event option").map(&:text)).to eq(["All events", "click", "scroll", "sign_up"])
    expect(page.at_css("#event-filter-event option[selected]").text).to eq("scroll")
    expect(page.css("#event-filter-key_event option").map(&:text)).to eq(["All events", "click", "sign_up"])
    expect(page.css("dl button[aria-describedby]").map { |button| button["aria-label"] }).to include("About Event count (scroll)")
    expect(page.at_css("nav[aria-label=Breakdown] a[href*='page-titles']")["href"]).to include("event=scroll")
  end


  it "counts every event when GA can't be asked for the chosen one, and says so" do
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 3, event_count: 9)
    # A day earlier, since the before block already holds yesterday's scroll for /post/a.
    Google::Analytics::EventStat.create!(date: yesterday - 1, page_path: "/post/a", event_name: "scroll", event_count: 2)

    get google_analytics_engagement_breakdown_path("pages-and-screens", event: "scroll")

    expect(table_rows.first[-2]).to eq("8 (72.73%)")
    expect(Nokogiri::HTML5(response.body).text.squish)
      .to include("Couldn't get the chosen event's figures from Google Analytics (not asked in specs), so Event count and Key events count every event.")
  end


  it "ignores an event that wasn't triggered in the period" do
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 3, event_count: 9)

    get google_analytics_engagement_breakdown_path("pages-and-screens", event: "download")

    expect(table_rows.first[-2]).to eq("6 (66.67%)")
    expect(Nokogiri::HTML5(response.body).text).not_to include("chosen event")
  end

  it "folds pages that reported the same title into one row, as GA's Pages and screens report does, searchable by title" do
    Google::Analytics::PageTitleStat.create!(date: yesterday, page_path: "/", page_title: "Harshal V. LADHE", views: 5)
    Google::Analytics::PageTitleStat.create!(date: yesterday, page_path: "/tutorial/a", page_title: "Harshal V. LADHE", views: 2)
    Google::Analytics::PageTitleStat.create!(date: yesterday, page_path: "/post/b", page_title: "CSS Grid | Harshal V. LADHE", views: 1)

    get google_analytics_engagement_breakdown_path("page-titles", page_title: "ladhe")

    expect(Nokogiri::HTML5(response.body).css("thead th").map { |cell| (cell.at_css("a") || cell).text.squish }).to include("Page title and screen class")
    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "Harshal V. LADHE", "7 (87.5%)"], ["2", "CSS Grid | Harshal V. LADHE", "1 (12.5%)"]])
  end

  it "lists only key events, asking GA for those events' users alone" do
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("key-events")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "click", "1 (100%)"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call).with(hash_including(filters: [["isKeyEvent", "EXACT", "true"]])).at_least(:once)
    expect(page.at_css("#event-filter-event")).to be_nil
  end

  it "says from when each figure was first counted, only where the period reaches back before it" do
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "article_read", event_count: 2)
    Google::Analytics::EventStat.create!(date: yesterday - 5, page_path: "/post/a", event_name: "like", event_count: 1)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("events", from: "2026-06-01", to: yesterday.iso8601)
    expect(page.text.squish).to include("Analytics figures are counted from 18 Jun, 2026, two days after the blog went live on 16 Jun, 2026")
    expect(page.text.squish).to include("Liked from 7 Oct, 2026 and Finished reading from 12 Oct, 2026.")

    get google_analytics_engagement_breakdown_path("event-labels", from: "2026-10-01", to: yesterday.iso8601)
    expect(page.at_css("[role=note]").text.squish).to eq(
      "Event labels are counted from 24 Oct, 2026, when event_label was registered in Google Analytics, so earlier days in this period have none."
    )

    get google_analytics_engagement_breakdown_path("events", from: yesterday.iso8601, to: yesterday.iso8601)
    expect(page.text).not_to include("are counted from")
    expect(page.text).not_to include("Counted only since")
  end

  it "lists the links readers follow off the site, asking GA for click events alone" do
    Google::Analytics::OutboundLinkStat.create!(date: yesterday, page_path: "/post/a", link_url: "https://github.com/x", event_count: 4, total_users: 3)
    Google::Analytics::OutboundLinkStat.create!(date: yesterday, page_path: "/post/b", link_url: "https://github.com/x", event_count: 1, total_users: 1)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("outbound-links", link_url: "github")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "https://github.com/x", "5 (100%)"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(dimensions: {link_url: "linkUrl"}, filters: [["eventName", "EXACT", "click"], ["linkUrl", "CONTAINS", "github"]])).at_least(:once)
  end

  it "lists clicks by their label, asking GA for the label's own figures" do
    Google::Analytics::EventLabelStat.create!(date: yesterday, page_path: "/post/a", event_name: "share", event_label: "x", event_count: 3, total_users: 2)
    Google::Analytics::EventLabelStat.create!(date: yesterday, page_path: "/post/b", event_name: "share", event_label: "x", event_count: 1, total_users: 1)
    Google::Analytics::EventLabelStat.create!(date: yesterday, page_path: "/", event_name: "social_click", event_label: "GitHub", event_count: 2, total_users: 2)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_engagement_breakdown_path("event-labels", event_label: "x")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "share", "x"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(filters: include(["customEvent:event_label", "CONTAINS", "x"]))).at_least(:once)
  end

  it "exports both totals and daily rows" do
    get google_analytics_engagement_breakdown_path("events", format: :csv)
    expect(CSV.parse(response.body).first).to eq(["Event", "Event count", "Total users", "Active users", "Event count per active user", "Events per session", "Key events"])

    get google_analytics_engagement_breakdown_path("events", format: :csv, export: "daily")
    expect(CSV.parse(response.body, headers: true).size).to eq(3)
  end

  it "sums the blog's own reader events per 100 views on the events tab" do
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "copy_code", event_count: 4)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 200)

    get google_analytics_engagement_path

    bar = page.at_css("section[aria-labelledby=reader-interactions] li[data-tip]")
    expect(bar.text.squish).to eq("Copied code (2.0)")
    expect(bar.at_css("a")["href"]).to start_with(google_analytics_event_path("copy_code"))
    expect(JSON.parse(bar["data-tip"])["rows"].first["value"]).to eq("4")
  end

    it "draws the charted rows' lines and bars against the period compared with, only once one is picked" do
    Google::Analytics::EventStat.create!(date: yesterday - 55, page_path: "/post/a", event_name: "scroll", event_count: 2)

    get google_analytics_engagement_path

    expect(legend).to include("Total", "Total, 18 Aug, 2026 – 14 Sep, 2026", "scroll, 18 Aug, 2026 – 14 Sep, 2026")
    expect(page.css("#chart-ranking ~ div li").first["data-tip"]).to include("18 Aug, 2026 – 14 Sep, 2026")

    get google_analytics_engagement_path(compare: "off")

    expect(legend).to eq(%w[Total scroll click])
  end

it "sets each reader event's count against the period compared with, only once one is picked" do
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "copy_code", event_count: 4)
    Google::Analytics::EventStat.create!(date: yesterday - 55, page_path: "/post/a", event_name: "copy_code", event_count: 2)
    Google::Analytics::Stat.create!(date: yesterday, page_path: "/post/a", views: 200)

    get google_analytics_engagement_path

    expect(page.at_css("section[aria-labelledby=reader-interactions] li[data-tip]").text.squish).to eq("Copied code (2.0) (+100%)")

    get google_analytics_engagement_path(compare: "off")

    expect(page.at_css("section[aria-labelledby=reader-interactions] li[data-tip]").text.squish).to eq("Copied code (2.0)")
  end
end
