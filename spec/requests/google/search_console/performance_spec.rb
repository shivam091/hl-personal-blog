# encoding: UTF-8

require "rails_helper"

RSpec.describe "Search Console performance", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  def stat(attributes)
    Google::SearchConsole::Stat.create!({search_type: "web", page: "https://example.com/post/a", page_path: "/post/a", date: yesterday}.merge(attributes))
  end

  def site_stat(attributes)
    stat({page: nil, page_path: nil}.merge(attributes))
  end

  describe "GET /google/search-console/performance" do
    it "totals each page over the last 28 days, with CTR and impression-weighted position" do
      stat(date: yesterday, clicks: 3, impressions: 100, position: 2.0)
      stat(date: yesterday - 1, clicks: 1, impressions: 300, position: 6.0)
      stat(date: yesterday - 40, clicks: 50, impressions: 50, position: 1.0)
      stat(page: "https://example.com/post/b", page_path: "/post/b", clicks: 9, impressions: 10, position: 1.0)
      stat(query: "css grid", clicks: 99, impressions: 99)
      site_stat(clicks: 13, impressions: 410, position: 4.9)

      get google_search_console_performance_breakdown_path("pages", trend: "clicks,impressions,ctr,position")

      expect(response).to have_http_status(:ok)
      rows = Nokogiri::HTML5(response.body).css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
      expect(rows).to eq([
        ["1", "https://example.com/post/b", "9", "10", "90.0%", "1.0"],
        ["2", "https://example.com/post/a", "4", "400", "1.0%", "5.0"]
      ])
      totals = Nokogiri::HTML5(response.body).css("dl dd.text-2xl").map(&:text)
      expect(totals).to eq(["13", "410", "3.2%", "4.9"])
      expect(Nokogiri::HTML5(response.body).css("dl [role=tooltip]").map { |tip| tip.text.strip }).to eq([
        "How often someone clicked a link from Google to your site.",
        "How often someone saw a link to your site on Google.",
        "Click-through rate: the calculation of clicks ÷ impressions.",
        "A relative ranking of the position of your link on Google, where 1 is the topmost position. Averaged over impressions, so lower is better."
      ])
    end

    it "shows Search Console's site-wide totals, which count a result once rather than once per page shown" do
      stat(clicks: 3, impressions: 30)
      stat(page: "https://example.com/post/b", page_path: "/post/b", clicks: 2, impressions: 30)
      site_stat(clicks: 4, impressions: 30)

      get google_search_console_performance_breakdown_path("pages")
      expect(Nokogiri::HTML5(response.body).css("dl dd.text-2xl").first(2).map(&:text)).to eq(["4", "30"])

      get google_search_console_performance_breakdown_path("pages", path: "/post/b")
      expect(Nokogiri::HTML5(response.body).css("dl dd.text-2xl").first(2).map(&:text)).to eq(["2", "30"])
    end

    it "compares the totals with the period before unless the comparison is turned off" do
      site_stat(clicks: 3, impressions: 10)
      site_stat(date: yesterday - 55, clicks: 2, impressions: 10)

      get google_search_console_performance_breakdown_path("pages")
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("dl dd.text-xs").text.squish).to eq("50.0%")
      expect(page.at_css("#period-compare a[aria-current]").text).to include("Previous period")
      expect(page.at_css("#compare-countries")).to be_nil
      expect(page.at_css("nav[aria-label=Breakdown] a[href*='queries']")["href"]).not_to include("compare")

      get google_search_console_performance_breakdown_path("pages", compare: "off")
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("dl dd.text-xs")).to be_nil
      expect(page.css("figure polyline[data-previous]")).to be_empty
      expect(page.at_css("nav[aria-label=Breakdown] a[href*='queries']")["href"]).to include("compare=off")
    end

    it "compares one search type with another over the same dates, keeping it on every link" do
      site_stat(clicks: 6, impressions: 40)
      site_stat(search_type: "image", clicks: 2, impressions: 20)
      site_stat(search_type: "web", date: yesterday - 55, clicks: 1, impressions: 10)

      get google_search_console_performance_breakdown_path("pages", type: "web", vs: "image")
      page = Nokogiri::HTML5(response.body)
      expect(page.css("dl dd.text-2xl").first(2).map(&:text)).to eq(["6", "40"])
      expect(page.css("dl dd.text-xs").first(2).map { |change| change.text.squish }).to eq(["200.0%", "100.0%"])
      expect(page.at_css("dl dd.text-xs")["title"]).to eq("Compared with Image")
      expect(page.text).to include("Dotted: Image, lined up under these dates")
      expect(page.at_css("#compare-type button").text.squish).to eq("Image")
      expect(page.at_css("#compare-type-menu a[aria-current]").text.squish).to eq("Image")
      expect(page.css("#compare-type-menu a").map { |link| link.text.squish }).not_to include("Web")
      expect(page.at_css("#period-compare")).to be_present
      expect(page.at_css("nav[aria-label=Breakdown] a[href*='days']")["href"]).to include("vs=image")
      expect(page.css("#period-compare a").map { |link| link["href"] }).to all(satisfy { |href| !href.include?("vs=") })

      get google_search_console_performance_breakdown_path("days", type: "web", vs: "image")
      row = Nokogiri::HTML5(response.body).at_css("tbody tr").text.squish
      expect(row).to include("(+200%)")
    end

    it "says why a search type can't be compared, and asks for a type first" do
      site_stat(clicks: 6, impressions: 40)
      site_stat(search_type: "discover", clicks: 0, impressions: 0)

      get google_search_console_performance_breakdown_path("pages", type: "web", vs: "discover")
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("#compare-type [role=status]").text).to eq("Discover has no impressions here over these dates, so there's nothing to compare it with.")
      expect(page.at_css("dl dd.text-xs")["title"]).not_to eq("Compared with Discover")

      get google_search_console_performance_breakdown_path("pages", vs: "image")
      expect(Nokogiri::HTML5(response.body).at_css("#compare-type").text.squish).to include("Pick a search type above")
    end

    it "makes no comparison with a period from before the first sync" do
      site_stat(clicks: 3, impressions: 10)
      site_stat(date: yesterday - 30, clicks: 2, impressions: 10)

      get google_search_console_performance_breakdown_path("pages", from: "2026-09-25", to: "2026-10-12", compare: "previous")

      expect(Nokogiri::HTML5(response.body).at_css("dl dd.text-xs").text.squish).to eq("No earlier data")
    end

    it "lists another breakdown site-wide, as Search Console's tabs do" do
      site_stat(query: "css grid", clicks: 5, impressions: 20)
      stat(query: "css grid", clicks: 3, impressions: 20)
      stat(page: "https://example.com/post/b", page_path: "/post/b", query: "css grid", clicks: 3, impressions: 20)

      get google_search_console_performance_breakdown_path("queries")

      expect(Nokogiri::HTML5(response.body).css("tbody tr").map { |row| row.css("td")[2].text }).to eq(["5"])
    end

    it "totals each day, newest first, site-wide or for the pages searched" do
      site_stat(date: yesterday - 1, clicks: 2, impressions: 20)
      site_stat(date: yesterday, clicks: 3, impressions: 30)
      site_stat(date: yesterday, query: "css grid", clicks: 9, impressions: 9)
      stat(date: yesterday, clicks: 1, impressions: 10)
      stat(date: yesterday, page: "https://example.com/post/b", page_path: "/post/b", clicks: 5, impressions: 10)

      get google_search_console_performance_breakdown_path("days")
      rows = Nokogiri::HTML5(response.body).css("tbody tr").map { |row| row.css("td").first(4).map { |cell| cell.text.squish } }
      expect(rows).to eq([["1", "12 Oct, 2026", "3", "30"], ["2", "11 Oct, 2026", "2", "20"]])
      expect(Nokogiri::HTML5(response.body).at_css("th[aria-sort=descending]").text.squish).to eq("Date")
      expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breakdown] a[aria-current=page]").text).to eq("Days")

      get google_search_console_performance_breakdown_path("days", path: "/post/a")
      expect(Nokogiri::HTML5(response.body).css("tbody tr td:nth-child(3)").map(&:text)).to eq(["1"])

      get google_search_console_performance_breakdown_path("days", format: :csv)
      expect(CSV.parse(response.body).drop(1).map(&:first)).to eq(["2026-10-12", "2026-10-11"])
    end

    it "links each day to the report narrowed to that day, keeping the search type and page searched" do
      stat(date: yesterday - 1, clicks: 2, impressions: 20)

      get google_search_console_performance_breakdown_path("days", type: "web", path: "/post")

      link = Nokogiri::HTML5(response.body).at_css("tbody tr td:nth-child(2) a")
      expect(link["href"]).to eq("/google/search-console/performance/days?from=2026-10-11&path=%2Fpost&to=2026-10-11&type=web")
      expect(link["title"]).to eq("Show 11 Oct, 2026 only")
    end

    it "lists another breakdown, keeping the period, search type and every search" do
      stat(query: "css grid", clicks: 5, impressions: 20, position: 3.0)
      stat(query: "flexbox", clicks: 1, impressions: 20, position: 3.0)

      get google_search_console_performance_breakdown_path("queries", from: "2026-10-01", to: "2026-10-12", type: "web", path: "/post", query: "css")

      expect(response.body).to include("css grid")
      expect(response.body).not_to include("flexbox")
      nav = Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breakdown]")
      expect(nav.at_css("a[aria-current=page]").text).to eq("Queries")
      expect(nav.at_css("a").attr("href")).to eq("/google/search-console/performance/pages?from=2026-10-01&path=%2Fpost&query=css&to=2026-10-12&type=web")
    end

    it "shows the pages breakdown at the bare path, keeping the query" do
      get google_search_console_performance_path(from: "2026-10-01")

      expect(response).to have_http_status(:ok)
      expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breakdown] a[aria-current=page]").text).to eq("Pages")
    end

    it "marks the report as the current Google page in the navigation" do
      get google_search_console_performance_breakdown_path("queries")

      expect(Nokogiri::HTML5(response.body).at_css("#nav-google a[aria-current=page]").text.strip).to eq("Performance")
    end

    it "carries the breakdown and period into sorting and page links" do
      30.times { |n| site_stat(query: format("query %02d", n), clicks: n, impressions: 100) }

      get google_search_console_performance_breakdown_path("queries", from: "2026-10-01", to: "2026-10-12")

      expect(response.body).to include("/google/search-console/performance/queries?from=2026-10-01&amp;page=2&amp;to=2026-10-12")
      expect(response.body).to include("/google/search-console/performance/queries?direction=asc&amp;from=2026-10-01&amp;sort=clicks&amp;to=2026-10-12")
      expect(Nokogiri::HTML5(response.body).css("tbody tr").first.text).to include("query 29")
    end

    it "filters by search type, counting clicks in each tab" do
      site_stat(clicks: 4, impressions: 10)
      site_stat(search_type: "image", clicks: 2, impressions: 10)

      get google_search_console_performance_breakdown_path("pages", type: "image")

      expect(response.body).to match(%r{All\s*<span[^>]*>6</span>})
      expect(response.body).to match(%r{Image\s*<span[^>]*>2</span>})
      expect(Nokogiri::HTML5(response.body).css("dl dd.text-2xl").first.text).to eq("2")
    end

    it "shows an empty state that suggests syncing" do
      get google_search_console_performance_breakdown_path("pages")

      expect(response.body).to include("No figures for 15 Sep, 2026 – 12 Oct, 2026. Sync to fetch them from Google.")
    end

    it "charts clicks and impressions by default, and keeps the ticked figures across sorting and breakdowns" do
      site_stat(date: yesterday - 1, clicks: 2, impressions: 100, position: 4.0)
      site_stat(date: yesterday, clicks: 3, impressions: 50, position: 1.0)
      stat(clicks: 3, impressions: 50, position: 1.0)

      get google_search_console_performance_breakdown_path("pages")

      page = Nokogiri::HTML5(response.body)
      expect(page.css("dl input[type=checkbox]").to_h { |box| [box["value"], box["checked"].present?] })
        .to eq("clicks" => true, "impressions" => true, "ctr" => false, "position" => false)
      expect(page.css("figure polyline").map { |line| line["stroke"] }.uniq).to contain_exactly("#1d4ed8", "#86198f")
      expect(page.css("figure span[class*='writing-mode']").map(&:text)).to eq(%w[Clicks Impressions])

      get google_search_console_performance_breakdown_path("pages", trend: "position,ctr")

      page = Nokogiri::HTML5(response.body)
      expect(page.css("figure span[class*='writing-mode']").map(&:text)).to eq(["CTR", "Average position"])
      expect(page.at_css("nav[aria-label=Breakdown] a[href*='queries']")["href"]).to include("trend=ctr%2Cposition")
      expect(page.at_css("thead a[href*='sort']")["href"]).to include("trend=ctr%2Cposition")
    end

    it "shows only the ticked figures' columns in the table, or every one when none is ticked" do
      stat(clicks: 3, impressions: 100, position: 2.0)
      site_stat(clicks: 3, impressions: 100, position: 2.0)
      headings = -> { Nokogiri::HTML5(response.body).css("thead tr").first.css("th").map { |cell| cell.text.squish }.last(4) }

      get google_search_console_performance_breakdown_path("pages")
      expect(headings.()).to eq(["#", "Page", "Clicks", "Impressions"])

      get google_search_console_performance_breakdown_path("pages", trend: "position,ctr")
      expect(headings.()).to eq(["#", "Page", "CTR", "Average position"])
      expect(Nokogiri::HTML5(response.body).css("tbody tr").first.css("td").map { |cell| cell.text.squish }.last(2)).to eq(["3.0%", "2.0"])

      get google_search_console_performance_breakdown_path("pages", trend: "")
      expect(Nokogiri::HTML5(response.body).css("thead tr").first.css("th").map { |cell| cell.text.squish }.last(4))
        .to eq(["Clicks", "Impressions", "CTR", "Average position"])
    end

    it "works out a week's CTR and position from the week's own counts" do
      site_stat(date: Date.new(2026, 10, 4), clicks: 1, impressions: 10, position: 2.0)
      site_stat(date: Date.new(2026, 10, 5), clicks: 9, impressions: 90, position: 12.0)
      site_stat(date: Date.new(2026, 10, 11), clicks: 5, impressions: 5, position: 1.0)

      get google_search_console_performance_breakdown_path("pages", trend: "ctr,position", by: "week",
        from: "2026-10-04", to: "2026-10-12")

      readouts = Nokogiri::HTML5(response.body).css("figure [data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }
      expect(readouts.map { |tip| [tip["title"], tip["rows"].map { |row| row["value"] }] }).to eq([
        ["Week 1", ["10.0%", "11.0"]],
        ["Week 2", ["100.0%", "1.0"]]
      ])
    end

    it "colours each figure's numbers in the table as its line" do
      stat(clicks: 3, impressions: 100, position: 2.0)
      site_stat(clicks: 3, impressions: 100, position: 2.0)

      get google_search_console_performance_breakdown_path("pages", trend: "clicks,impressions,ctr,position")

      cells = Nokogiri::HTML5(response.body).css("tbody tr").first.css("td span[style]").map { |cell| [cell.text, cell["style"]] }
      expect(cells).to eq([["3", "color: #1d4ed8"], ["100", "color: #86198f"], ["3.0%", "color: #0e8aa6"], ["2.0", "color: #a16207"]])
    end

    it "narrows the report to a value clicked in the table, searching it exactly" do
      stat(query: "css", clicks: 2, impressions: 10)
      stat(query: "css grid", clicks: 5, impressions: 20)
      site_stat(query: "css", clicks: 2, impressions: 10)
      site_stat(query: "css grid", clicks: 5, impressions: 20)

      get google_search_console_performance_breakdown_path("queries")
      link = Nokogiri::HTML5(response.body).css("tbody td a").find { |a| a.text == "css" }
      expect(link["href"]).to eq("/google/search-console/performance/queries?query=css&query_match=exact")

      get link["href"]
      page = Nokogiri::HTML5(response.body)
      expect(page.css("tbody tr").map { |row| row.css("td")[1].text.squish }).to eq(["css"])
      expect(page.css("dl dd.text-2xl").first(2).map(&:text)).to eq(%w[2 10])
      expect(page.text).to include("Query is “css”")
    end

    it "lists each query with each page shown for it, from the per-page rows" do
      stat(query: "css grid", clicks: 5, impressions: 20)
      stat(query: "css grid", page: "https://example.com/post/b", page_path: "/post/b", clicks: 2, impressions: 30)
      site_stat(query: "css grid", clicks: 6, impressions: 40)
      site_stat(clicks: 6, impressions: 40)

      get google_search_console_performance_breakdown_path("query-pages")

      page = Nokogiri::HTML5(response.body)
      expect(page.css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }).to eq(["#", "Query", "Page", "Clicks", "Impressions"])
      expect(page.css("tbody tr").map { |row| row.css("td").drop(1).map { |cell| cell.text.squish } }).to eq([
        ["css grid", "https://example.com/post/a", "5", "20"],
        ["css grid", "https://example.com/post/b", "2", "30"]
      ])
      expect(page.css("dl dd.text-2xl").first(2).map(&:text)).to eq(%w[6 40])
    end

    it "lists the stored hours newest first, in Pacific Time, totalled and charted on their own" do
      hour = ->(at, **attributes) { Google::SearchConsole::HourStat.create!(search_type: "web", date: yesterday, hour_at: at, **attributes) }
      hour.(Time.utc(2026, 10, 12, 20), clicks: 3, impressions: 30, position: 2.0)
      hour.(Time.utc(2026, 10, 12, 22), clicks: 1, impressions: 10, position: 4.0)
      hour.(Time.utc(2026, 10, 12, 22), page: "https://example.com/post/a", page_path: "/post/a", clicks: 1, impressions: 10, position: 4.0)
      site_stat(clicks: 50, impressions: 500)

      get google_search_console_performance_breakdown_path("hours")

      page = Nokogiri::HTML5(response.body)
      expect(page.css("tbody tr").map { |row| row.css("td").drop(1).map { |cell| cell.text.squish } }).to eq([
        ["Mon 12 Oct, 15:00", "1", "10"], ["Mon 12 Oct, 13:00", "3", "30"]
      ])
      expect(page.css("dl dd.text-2xl").map(&:text)).to eq(["4", "40", "10.0%", "2.5"])
      tips = page.css("figure [data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }
      expect(tips.map { |tip| tip["title"] }).to eq(["Mon, 12 Oct 2026, 13:00 PDT", "Mon, 12 Oct 2026, 14:00 PDT", "Mon, 12 Oct 2026, 15:00 PDT"])
      expect(tips[1]["rows"].map { |row| row["value"] }).to eq(["No data", "No data"])
      expect(page.at_css("#trend-by")).to be_nil

      Google::SearchConsole::AppearanceStat.create!(search_type: "web", date: yesterday, appearance: "VIDEO")
      get google_search_console_performance_breakdown_path("hours", appearance: "VIDEO")
      expect(Nokogiri::HTML5(response.body).text).to include("Search Console's hours aren't stored by search appearances.")
    end

    it "says the hours aren't stored by query, country or device" do
      Google::SearchConsole::HourStat.create!(search_type: "web", date: yesterday, hour_at: Time.utc(2026, 10, 12, 20), clicks: 9, impressions: 90)
      %w[US IN].each { |country| Google::SearchConsole::CountryStat.create!(search_type: "web", date: yesterday, country: country) }

      get google_search_console_performance_breakdown_path("hours", country: "IN")
      page = Nokogiri::HTML5(response.body)
      expect(page.text).to include("Search Console's hours aren't stored by countries. Remove the country search, or open Days.")
      expect(page.css("tbody tr")).to be_empty
    end

    it "notes the days Google may still revise in their readouts on the trend" do
      site_stat(date: yesterday - 1, clicks: 2, impressions: 20)
      site_stat(clicks: 3, impressions: 30)
      Google::SearchConsole::FinalDate.record(yesterday)

      get google_search_console_performance_path
      notes = Nokogiri::HTML5(response.body).css("figure [data-tip]").map { |hit| JSON.parse(hit["data-tip"])["note"] }
      expect(notes.last).to eq("Data is still being collected")
      expect(notes[0...-1].compact).to be_empty
    end

    it "dots the period compared with under the trend, a year back when asked" do
      site_stat(clicks: 3, impressions: 30)
      site_stat(date: yesterday - 55, clicks: 1, impressions: 10)
      site_stat(date: yesterday.prev_year, clicks: 7, impressions: 70)
      site_stat(date: (yesterday - 27).prev_year, clicks: 1, impressions: 10)

      get google_search_console_performance_breakdown_path("pages", compare: "previous")
      page = Nokogiri::HTML5(response.body)
      expect(page.css("figure polyline[data-previous]")).to be_present
      expect(JSON.parse(page.css("figure [data-tip]").last["data-tip"])["rows"].find { |row| row["name"] == "Clicks" && row["dotted"] })
        .to include("value" => "No data", "period" => "Mon, 14 Sep 2026")

      get google_search_console_performance_breakdown_path("pages", compare: "year")
      page = Nokogiri::HTML5(response.body)
      expect(JSON.parse(page.css("figure [data-tip]").last["data-tip"])["rows"].find { |row| row["name"] == "Clicks" && row["dotted"] })
        .to include("value" => "7", "period" => "Sun, 12 Oct 2025")
      expect(page.text).to include("Dotted: 15 Sep, 2025 – 12 Oct, 2025")
      expect(page.at_css("nav[aria-label=Breakdown] a[href*='queries']")["href"]).to include("compare=year")
      expect(page.at_css("#period-compare a[aria-current]").text).to include("Same period last year")
    end

    it "gives a query's pages from its own rows, and says why its countries can't be shown" do
      stat(query: "css grid", clicks: 5, impressions: 20)
      stat(page: "https://example.com/post/b", page_path: "/post/b", query: "flexbox", clicks: 1, impressions: 20)
      Google::SearchConsole::CountryStat.create!(search_type: "web", date: yesterday, country: "IN", clicks: 9, impressions: 9)

      get google_search_console_performance_breakdown_path("pages", query: "css grid", query_match: "exact")
      expect(Nokogiri::HTML5(response.body).css("tbody tr td:nth-child(2)").map(&:text).map(&:squish)).to eq(["https://example.com/post/a"])

      get google_search_console_performance_breakdown_path("countries", query: "css grid", query_match: "exact")
      expect(Nokogiri::HTML5(response.body).at_css("tbody")).to be_nil
      expect(response.body).to include("aren&#39;t stored split by countries and queries together")
    end

    it "offers copying, opening and inspecting each page, inspecting in the admin where it has a verdict" do
      stat(clicks: 3, impressions: 10)
      stat(page: "https://example.com/post/b", page_path: "/post/b", clicks: 1, impressions: 10)
      crawled = CrawledPage.create!(url: "https://example.com/post/a", last_modified_at: Time.current)
      inspection = Google::SearchConsole::UrlInspection.create!(crawled_page: crawled, verdict: "PASS", inspected_at: Time.current)

      get google_search_console_performance_breakdown_path("pages")

      rows = Nokogiri::HTML5(response.body).css("tbody tr")
      actions = rows.first.css("td")[1]
      expect(actions.at_css("button[data-controller=clipboard]")["data-clipboard-text-value"]).to eq("https://example.com/post/a")
      expect(actions.css("[aria-label]").map { |action| action["aria-label"] }).to eq(["Copy URL to clipboard", "Open in new tab", "Inspect URL", "Mark as requested"])
      expect(actions.at_css("a[aria-label='Open in new tab']")["href"]).to eq("https://example.com/post/a")
      expect(actions.at_css("a[aria-label='Inspect URL']")["href"]).to eq(google_search_console_url_inspection_path(inspection))
      expect(rows[1].at_css("form[action$='/inspect'] button[aria-label='Inspect URL']")).to be_nil
      expect(actions.at_css("a[title]")["href"]).to eq("/google/search-console/performance/pages?path=%2Fpost%2Fa&path_match=exact")
    end

    it "offers a query's split under its column rather than as a tab" do
      Google::SearchConsole::Stat.create!(search_type: "web", date: yesterday, query: "css grid", page: "https://example.com/post/a", page_path: "/post/a", clicks: 1)
      Google::SearchConsole::CountryStat.create!(search_type: "web", date: yesterday, country: "US", clicks: 1)
      Google::SearchConsole::DeviceStat.create!(search_type: "web", date: yesterday, device: "mobile", clicks: 1)

      get google_search_console_performance_breakdown_path("query-pages", type: "web")

      page = Nokogiri::HTML5(response.body)
      tabs = page.css("nav[aria-label=Breakdown] a")
      expect(tabs.map { |tab| tab.text.squish }).to eq(["Pages", "Queries", "Countries", "Devices", "Search appearance", "Days", "Hours"])
      expect(tabs.find { |tab| tab["aria-current"] }.text.squish).to eq("Queries")
      split = page.at_css("thead select#breakdown-split")
      expect(split.ancestors("th").first.text).to include("Query")
      expect(split.css("option").map { |option| option.text }).to eq(["No split", "By page"])
      expect(split.at_css("option[selected]")["value"]).to eq(google_search_console_performance_breakdown_path("query-pages", type: "web"))

      get google_search_console_performance_breakdown_path("countries")
      expect(Nokogiri::HTML5(response.body).at_css("thead select#breakdown-split")).to be_nil

      get google_search_console_performance_breakdown_path("devices")
      expect(Nokogiri::HTML5(response.body).at_css("thead select#breakdown-split")).to be_nil
    end

    it "refuses an unknown breakdown" do
      get "/google/search-console/performance/nonsense"

      expect(response).to have_http_status(:not_found)
    end

    it "exports each figure with its change from the period before, as the list shows it" do
      stat(clicks: 3, impressions: 100, position: 2.0)
      stat(date: Date.new(2026, 8, 18), clicks: 2, impressions: 100, position: 4.0)

      get google_search_console_performance_breakdown_path("pages", format: :csv)

      expect(CSV.parse(response.body)).to eq([
        ["Page", "Clicks", "Impressions", "CTR", "Average position"],
        ["https://example.com/post/a", "3 (+50%)", "100 (0%)", "0.03 (+50%)", "2.0 (-50%)"]
      ])
    end

    it "exports the listed totals, and the daily rows behind them" do
      stat(clicks: 3, impressions: 100, position: 2.0)
      stat(date: yesterday - 1, clicks: 1, impressions: 300, position: 6.0)

      get google_search_console_performance_breakdown_path("pages", format: :csv)
      expect(response.headers["Content-Disposition"]).to include("search-console-pages-2026-09-15-to-2026-10-12.csv")
      expect(CSV.parse(response.body)).to eq([
        ["Page", "Clicks", "Impressions", "CTR", "Average position"],
        ["https://example.com/post/a", "4", "400", "0.01", "5.0"]
      ])

      get google_search_console_performance_breakdown_path("pages", format: :csv, export: "daily")
      expect(response.headers["Content-Disposition"]).to include("search-console-pages-daily-")
      csv = CSV.parse(response.body, headers: true)
      expect(csv.map { |row| [row["Date"], row["Clicks"]] }).to eq([["2026-10-12", "3"], ["2026-10-11", "1"]])
    end
  end

  describe "POST /google/search-console/performance/sync" do
    it "queues a sync of just performance over the chosen days" do
      get google_search_console_performance_breakdown_path("pages")
      expect(Nokogiri::HTML5(response.body).at_css("#sync-dialog form")["action"]).to eq(google_search_console_performance_sync_path("pages"))

      expect {
        post google_search_console_performance_sync_path("queries"), params: {google_sync_range: {from: "2026-10-01", to: "2026-10-10"}}
      }.to change(SyncRequest, :count).by(1)
      request = SyncRequest.last
      expect(request).to have_attributes(kind: "search_console_performance", from_date: Date.new(2026, 10, 1), to_date: Date.new(2026, 10, 10))
      expect(Google::SearchConsole::SyncJob).to have_been_enqueued.with(10, "2026-10-10", only: ["performance"], request_id: request.id.to_s)
      expect(response).to redirect_to(google_search_console_performance_breakdown_path("queries"))
      expect(flash[:notice]).to start_with("Syncing 10 days (1 Oct, 2026 to 10 Oct, 2026) from Search Console in the background.")
    end

    it "redraws just the dialog with its errors from Turbo" do
      post google_search_console_performance_sync_path("pages"), params: {google_sync_range: {from: "2024-01-01", to: "2026-12-01"}},
        headers: {"Accept" => "text/vnd.turbo-stream.html, text/html"}

      expect(response).to have_http_status(:unprocessable_content)
      stream = Nokogiri::HTML5.fragment(response.body).at_css("turbo-stream[action=replace][target=sync-dialog]")
      dialog = stream.at_css("[data-modal-open-value=true] dialog")
      expect(dialog.at_css("[role=alert] h2").text.squish).to eq("2 problems kept this sync from starting")
      expect(dialog.at_css("#google_sync_range_from_error").text.squish).to eq("Start date can't be before 13 Jun, 2025, the oldest day Google keeps")
      expect(dialog.at_css("#google_sync_range_to_error").text.squish).to eq("End date can't be in the future")
      expect(enqueued_jobs).to be_empty
      expect(SyncRequest.count).to eq(0)
    end

    it "shows the report again with the dialog open without Turbo" do
      post google_search_console_performance_sync_path("pages"), params: {google_sync_range: {from: "garbage", to: ""}}

      expect(response).to have_http_status(:unprocessable_content)
      dialog = Nokogiri::HTML5(response.body).at_css("[data-modal-open-value=true] dialog")
      expect(dialog.text.squish).to include("Start date is not a valid date", "End date can't be blank")
    end
  end
end
