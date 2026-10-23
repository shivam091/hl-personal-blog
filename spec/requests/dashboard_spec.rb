# encoding: UTF-8

require "rails_helper"

RSpec.describe "Dashboard", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  # Shaped like the frontend writes them, so the page reads real data.
  def seed
    PageView.collection.insert_many([
      {"_id" => "/post/busy", "slug" => "/post/busy", "url" => "https://blog.example.com/post/busy",
       "countriesByDay" => {"2026-10-10" => {"IN" => 120, "US" => 30}, "2026-09-01" => {"US" => 5}},
       "devices" => {"desktop" => 3, "mobile" => 1}, "referrers" => {"google_com" => 2, "direct" => 2}},
      {"_id" => "/post/quiet", "slug" => "/post/quiet", "url" => "https://blog.example.com/post/quiet",
       "countriesByDay" => {"2026-10-11" => {"DE" => 2}}}
    ])
    PageLike.collection.insert_one("_id" => "/post/busy", "slug" => "/post/busy", "likeCount" => 8,
      "countriesByDay" => {"2026-10-10" => {"IN" => 6}})
    NewsletterSubscriber.collection.insert_one("email" => "reader@example.com", "country" => "IN",
      "subscribedAt" => Time.zone.parse("2026-10-09 10:00"))
    Message.collection.insert_one("name" => "Asha", "email" => "asha@example.com", "message" => "Loved the post",
      "country" => "IN", "createdAt" => Time.zone.parse("2026-10-11 09:00"))
  end

  def page
    Nokogiri::HTML5(response.body)
  end

  def tiles
    page.css("dl > div").to_h { |tile| [tile.at_css("dt").xpath("text()").text.squish, tile.at_css("dd span").text.strip] }
  end

  it "shows changes and the period before unless the comparison is turned off" do
    seed

    get root_path
    expect(page.css("dl dd[title^='Compared with']")).to be_present
    expect(page.at_css("section[aria-labelledby=views-and-likes]").text).to include("17 Aug, 2026 – 13 Sep, 2026")
    expect(page.at_css("#period-compare a[aria-current]").text.squish).to eq("Previous period 17 Aug, 2026 – 13 Sep, 2026")
    expect(page.at_css("[aria-controls=period-compare]").text.squish).to eq("Compare: vs previous period")
    # No country is picked until the reader picks one.
    expect(page.at_css("#compare-countries").key?("hidden")).to be(true)
    expect(page.at_css("#compare-countries a[aria-current]")).to be_nil

    get root_path(compare: "off")
    expect(page.css("#kpis ~ * dd[title^='Compared with'], dl dd[title^='Compared with']")).to be_empty
    expect(page.at_css("section[aria-labelledby=views-and-likes]").text).not_to include("–")
    expect(page.at_css("#period-compare a[aria-current]").text.squish).to eq("No comparison")
  end

  it "shows each page's, type's and country's change beside its figure, and names what needs a comparison when it's off" do
    seed

    get root_path

    views = page.css("#top-pages ~ div table tbody tr").map { |row| row.css("td")[1].text.squish }
    expect(views.first).to match(/\A150 \(\+\d+%\)\z/)
    expect(views.last).to eq("2 (new)")

    get root_path(compare: "off")

    expect(page.css("#top-pages ~ div table tbody tr").map { |row| row.css("td")[1].text.squish }).to eq(%w[150 2])
    expect(page.at_css("#page-changes").parent.text).to include("shows once a comparison is picked")
    expect(page.at_css("#growing-countries").parent.text).to include("shows once a comparison is picked")
    expect(page.css("#country-funnel ~ div tbody tr td")[1].text.squish).to eq("120")
  end

  it "compares with a week back or with picked dates, even ones after the period" do
    seed

    get root_path(from: "2026-09-04", to: "2026-09-04", compare: "week")
    expect(page.at_css("[aria-controls=period-compare]").text.squish).to eq("Compare: vs same period last week")
    expect(page.at_css("#period-compare a[aria-current]").text.squish).to eq("Same period last week 28 Aug, 2026")

    get root_path(from: "2026-09-01", to: "2026-09-01", compare: "custom", vs_from: "2026-10-10", vs_to: "2026-10-11", country: "US")
    expect(page.at_css("[aria-controls=period-compare]").text.squish).to eq("Compare: vs custom range")
    expect(page.at_css("#compare-custom").key?("hidden")).to be(false)
    expect(page.at_css("#compare-custom input[name=vs_from]")["value"]).to eq("2026-10-10")
    form = page.css("#compare-custom input[type=hidden]").to_h { |input| [input["name"], input["value"]] }
    expect(form).to eq("from" => "2026-09-01", "to" => "2026-09-01", "compare" => "custom", "country" => "US")
    views = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Views") }
    expect(views.at_css("dd[title]")["title"]).to eq("Compared with 10 Oct, 2026 – 11 Oct, 2026")
    expect([views.at_css("dd[title]").text.squish, views.at_css("dd[title] .text-red-700")]).to match(["83.3%", be_present])
  end

  it "compares a country with another over the same days, from one menu with the country filter" do
    seed

    get root_path(country: "IN", compare: "country", vs: "US")
    expect(page.at_css("#compare-countries a[aria-current]")["href"]).to include("compare=country", "vs=US", "country=IN")
    expect(page.at_css("#period-country a[aria-current]")["href"]).to include("country=IN", "vs=US")
    views = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Views") }
    expect(views.at_css("dd[title]")["title"]).to eq("Compared with US")
    expect(views.at_css("dd[title]").text.squish).to eq("300.0%")
    expect(page.at_css("#growing-countries").parent.text).to include("comparing by period")

    get root_path(compare: "country", vs: "US", from: "2026-10-01", to: "2026-10-11")
    expect(page.css("#custom-period input[name=vs]").map { |input| input["value"] }).to eq(["US"])
    expect(page.at_css("nav[aria-label=Period] a")["href"]).to include("vs=US")
  end

  it "marks the days entries were published on the views chart, naming them in the day's readout" do
    seed
    FeedEntry.create!(url: "https://blog.example.com/post/busy", name: "Busy post", type: "post",
      published_at: Time.zone.parse("2026-10-10 08:00"), last_modified_at: Time.zone.parse("2026-10-10 08:00"))
    FeedEntry.create!(url: "https://blog.example.com/post/old", name: "Old post", type: "post",
      published_at: Time.zone.parse("2025-01-01"), last_modified_at: Time.zone.parse("2025-01-01"))

    get root_path

    chart = page.at_css("section[aria-labelledby=views-and-likes]")
    readouts = chart.css("rect[data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }
    published = readouts.select { |tip| tip["rows"].any? { |row| row["value"] == "Published" } }
    expect(published.map { |tip| [tip["title"], tip["rows"].last["name"]] }).to eq([["Sat, 10 Oct 2026", "Busy post"]])
    # One on the views chart and one on the likes chart.
    expect(chart.css("span[data-event]").size).to eq(2)
    likes = chart.css("g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.find { |tip| tip["title"] == "Sat, 10 Oct 2026" }
    expect(likes["rows"].last).to include("value" => "Published", "name" => "Busy post")
  end

  it "marks publishing days on the subscriber and search charts, by week where the chart is weekly" do
    seed
    FeedEntry.create!(url: "https://blog.example.com/post/busy", name: "Busy post", type: "post",
      published_at: Time.zone.parse("2026-10-10 08:00"), last_modified_at: Time.zone.parse("2026-10-10 08:00"))
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 10), page: "https://blog.example.com/post/busy",
      page_path: "/post/busy", clicks: 3, impressions: 40, position: 4.0)

    get root_path

    subscribers = page.at_css("#subscribers-growth ~ div")
    expect(subscribers.css("span[data-event]").size).to eq(2)
    week = subscribers.css("[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.find { |tip| tip["title"] == "Week of 5 Oct, 2026" }
    expect(week["rows"].last).to include("value" => "Published", "name" => "Busy post")
    expect(page.at_css("section[aria-labelledby=search]").css("span[data-event]").size).to eq(1)
  end

  it "lists what needs attention, linking each to where to look, and nothing when all is well" do
    get root_path
    expect(page.at_css("#anomalies")).to be_nil

    Google::SafeBrowsing::LinkCheck.create!(url: "https://bad.example.com/", threat_types: ["MALWARE"])

    get root_path

    link = page.at_css("#anomalies ~ ul a")
    expect(link.text.squish).to include("Unsafe outbound links")
    expect(link["href"]).to eq(google_safe_browsing_link_checks_path)
  end

  it "is the root page, marked current in the nav" do
    get root_path

    expect(response).to have_http_status(:ok)
    current = page.css("nav[aria-label=Main] a[aria-current=page][href='/']")
    expect(current.map { |link| link.text.strip }).to include("Dashboard")
  end

  it "shows the period's totals with charts, top pages, countries and the latest records" do
    seed

    get root_path

    expect(tiles).to eq("Views" => "152", "Likes" => "6", "Subscribers" => "1", "Messages" => "1", "Unique visitors" => "0")
    expect(page.css("section[aria-labelledby=views-and-likes] svg[role=img]").size).to eq(2)
    expect(page.css("#top-pages ~ div table tbody tr td:first-child").map { |td| td.text.strip }).to eq(%w[/post/busy /post/quiet])
    expect(page.at_css("#country-funnel ~ div tbody tr td").text.squish).to eq("🇮🇳 IN")
    expect(page.at_css("#referrers ~ div").text).to include("Search", "Direct")
    expect(response.body).to include("Loved the post", "reader@example.com", "Devices · all time")
    india = page.css("#countries ~ div svg path").map { |path| JSON.parse(path["data-tip"]) }.find do |tip|
      tip["title"] == "🇮🇳 India"
    end
    expect(india["rows"]).to eq([{"value" => "120", "name" => "views"}])
    expect(page.css("#country-shares ~ div table tbody tr th").map(&:text)).to eq(["Week of 5 Oct, 2026"])
  end

  it "narrows the figures to one country and keeps it in the period links" do
    seed

    get root_path(country: "us", from: "2026-08-01", to: "2026-10-12")

    expect(tiles["Views"]).to eq("35")
    expect(page.at_css("#period-country a[aria-current]")["href"]).to include("country=US")
    expect(page.at_css("nav[aria-label=Period] a[href*='from=2026-10-05']")["href"]).to include("country=US")
    expect(page.at_xpath("//nav[@aria-label='Period']//a[normalize-space()='28 days']")["href"]).to eq("/?country=US")
  end

  it "shows Google's figures beside the blog's own, with index coverage and freshness" do
    seed
    Google::SearchConsole::Stat.create!(
      search_type: "web",
      date: Date.new(2026, 10, 10),
      clicks: 12,
      impressions: 300,
      position: 4.0
    )
    Google::Analytics::Stat.create!(
      date: Date.new(2026, 10, 10),
      page_path: "/post/busy",
      views: 100
    )
    Google::Analytics::LandingPageStat.create!(
      date: Date.new(2026, 10, 10),
      page_path: "/post/busy",
      sessions: 80,
      engaged_sessions: 40
    )
    CrawledPage.create!(
      url: "https://blog.example.com/post/busy",
      last_modified_at: Time.zone.parse("2026-10-01"),
      indexed: true
    )
    CrawledPage.create!(
      url: "https://blog.example.com/post/quiet",
      last_modified_at: Time.zone.parse("2026-10-02")
    )

    get root_path

    search = page.css("section[aria-labelledby=search] dl > div").to_h do |tile|
      [tile.at_css("dt").xpath("text()").text.squish, tile.at_css("dd span").text.strip]
    end
    expect(search).to include("Clicks" => "12", "Impressions" => "300")

    analytics = page.css("section[aria-labelledby=analytics] dl > div").to_h do |tile|
      [tile.at_css("dt").xpath("text()").text.squish, tile.at_css("dd span").text.strip]
    end
    expect(analytics).to include("GA views" => "100", "Sessions" => "80", "Engagement rate" => "50%")

    expect(page.at_css("#index-coverage ~ div").text.squish).to include("1 of 2 pages indexed", "/post/quiet")
    expect(page.css("#data-freshness ~ div table tbody tr").size).to eq(SyncRequest::KINDS.size)
    expect(page.css("#country-funnel ~ div thead th").map { |th| th.text.strip }).to include("Search clicks", "GA views")
  end

  it "shows uploaded AI impressions beside search's own, except while a country is picked" do
    seed
    Google::SearchConsole::Stat.create!(search_type: "web", date: Date.new(2026, 10, 10), clicks: 12, impressions: 300, position: 4.0)
    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 10, 10), impressions: 42)

    get root_path
    search = page.css("section[aria-labelledby=search] dl > div").to_h do |tile|
      [tile.at_css("dt").xpath("text()").text.squish, tile.at_css("dd span").text.strip]
    end
    expect(search).to include("AI impressions · Web" => "42")

    expect(page.at_css("#generative-ai-freshness").text.squish).to include("Generative AI upload", "Up to #{I18n.l(Date.new(2026, 10, 10))}")

    get root_path(country: "IN")
    expect(page.at_css("section[aria-labelledby=search]").text.squish).to include("AI impressions aren't split by country")
    expect(page.css("section[aria-labelledby=search] dl dt").map { |dt| dt.text.squish }).not_to include(a_string_starting_with("AI impressions"))
  end

  it "links the Analytics card to its referrers, keeping the period" do
    get root_path(from: "2026-10-01", to: "2026-10-10")

    link = page.css("section[aria-labelledby=analytics] p a").find { |a| a.text.squish == "Referrers" }
    expect(link["href"]).to eq(google_analytics_acquisition_breakdown_path("referrers", from: "2026-10-01", to: "2026-10-10"))
  end

  it "counts unique visitors across the period, saying when the kept markers don't reach its start" do
    PageViewSeen.collection.insert_many([
      {"slug" => "/a", "day" => "2026-10-10", "ipHash" => "one", "country" => "IN"},
      {"slug" => "/b", "day" => "2026-10-11", "ipHash" => "one", "country" => "IN"},
      {"slug" => "/a", "day" => "2026-10-11", "ipHash" => "two", "country" => "US"}
    ])

    get root_path
    visitors = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Unique visitors") }
    expect(visitors.at_css("dd span").text).to eq("2")
    expect(visitors.text).to include("Counted from 10 Oct, 2026")

    get root_path(from: "2026-10-10", to: "2026-10-12", country: "IN")
    expect(tiles["Unique visitors"]).to eq("1")
  end

  it "splits each day's views into unique visitors and repeat views, from the day visitors were counted, beside the bots' share" do
    seed
    PageView.collection.update_one({"_id" => "/post/busy"}, {"$set" => {"visitorCount" => 150, "botCount" => 50}})
    PageViewSeen.collection.insert_many([
      {"slug" => "/post/busy", "day" => "2026-10-10", "ipHash" => "one", "country" => "IN"},
      {"slug" => "/post/quiet", "day" => "2026-10-11", "ipHash" => "one", "country" => "DE"},
      {"slug" => "/post/quiet", "day" => "2026-10-11", "ipHash" => "two", "country" => "DE"}
    ])

    get root_path

    card = page.at_css("#audience").parent
    days = card.css("g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
    expect(days.map { |day| [day["title"], day["rows"].map { |row| row["value"] }] }).to eq([
      ["Sat, 10 Oct 2026", %w[1 149]], ["Sun, 11 Oct 2026", %w[2 0]]
    ])
    expect(card.text.squish).to include("50 of 200 hits (25.0%)",
      "Unique visitors are counted from 10 Oct, 2026, as far back as the kept markers reach, so earlier days in this period have none.")
  end

  it "follows the period for devices and referrers once they're dated" do
    PageView.collection.insert_one("_id" => "/a", "slug" => "/a", "devices" => {"tablet" => 50}, "referrers" => {"bing_com" => 50},
      "devicesByDay" => {"2026-10-10" => {"mobile" => 3}},
      "referrersByDay" => {"2026-10-10" => {"google_com" => 3}})

    get root_path

    expect(page.at_css("#devices").text.strip).to eq("Devices")
    expect(page.at_css("#devices ~ div").text).to include("mobile")
    expect(page.at_css("#devices ~ div").text).not_to include("tablet")
    expect(page.at_css("#referrers ~ div").text).to include("Search")
    expect(response.body).to include("Dated from 10 Oct, 2026; earlier views are only in all-time totals.")
  end

  it "charts the device and referrer mix by week once they're dated" do
    PageView.collection.insert_one("_id" => "/a", "slug" => "/a",
      "devicesByDay" => {"2026-10-10" => {"mobile" => 3, "desktop" => 1}},
      "referrersByDay" => {"2026-10-10" => {"google_com" => 3, "direct" => 1}})

    get root_path

    devices = JSON.parse(page.at_css("#device-shares ~ div rect[data-tip]")["data-tip"])
    expect(devices["title"]).to eq("Week of 5 Oct, 2026")
    expect(devices["rows"].map { |row| [row["name"], row["value"]] }).to eq([
      ["Mobile · 3 views", "75.0%"], ["Desktop · 1 view", "25.0%"], ["Other · 0 views", "0.0%"]
    ])
    expect(page.css("#referrer-shares ~ div table thead th").map(&:text)).to eq(["Week", "google.com", "Direct", "Other"])
  end

  it "leaves out the mixes before devices and referrers are dated" do
    PageView.collection.insert_one("_id" => "/a", "slug" => "/a", "devices" => {"tablet" => 5})

    get root_path

    expect(page.at_css("#device-shares")).to be_nil
    expect(page.at_css("#referrer-shares")).to be_nil
  end

  it "falls back to all-time devices before any are dated" do
    PageView.collection.insert_one("_id" => "/a", "slug" => "/a", "devices" => {"tablet" => 5})

    get root_path

    expect(page.at_css("#devices").text.strip).to eq("Devices · all time")
    expect(page.at_css("#devices ~ div").text).to include("tablet")
  end

  it "shows empty states with no data" do
    get root_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include(
      "No views in this period.",
      "No messages yet.",
      "No Search Console figures yet.",
      "No Analytics figures yet.",
      "No crawled pages yet.",
      "No feed entries yet."
    )
  end

  it "puts the views and likes charts in weeks once picked, keeping the choice across periods" do
    seed

    get root_path(chart_by: "week")

    card = page.at_css("section[aria-labelledby=views-and-likes]")
    expect(card.at_css("select#views-and-likes-by option[selected]")["value"]).to eq("week")
    weeks = card.css("rect[data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }.select { |tip| tip["title"] == "Week of 5 Oct, 2026" }
    expect(weeks.first["rows"].first["value"]).to eq("152")
    expect(page.at_css("nav[aria-label=Period] a")["href"]).to include("chart_by=week")
  end

  it "draws the period before on the list-size, sign-up and message charts, and the heatmap's cells, unless comparison is off" do
    seed

    get root_path
    labels = page.css("#subscribers-growth [role=img], #messages-by-week [role=img]").map { |chart| chart["aria-label"] }
    expect(labels).to all(include("against"))
    tips = page.css("#page-country-heatmap ~ div [data-tip]").map { |cell| JSON.parse(cell["data-tip"]) }
    expect(tips.flat_map { |tip| tip["rows"] }).to include(a_hash_including("dotted" => true))

    get root_path(compare: "off")
    labels = page.css("#subscribers-growth [role=img], #messages-by-week [role=img]").map { |chart| chart["aria-label"] }
    expect(labels).not_to include(a_string_including("against"))
    tips = page.css("#page-country-heatmap ~ div [data-tip]").map { |cell| JSON.parse(cell["data-tip"]) }
    expect(tips.flat_map { |tip| tip["rows"] }).not_to include(a_hash_including("dotted" => true))
  end
end
