# encoding: UTF-8

require "rails_helper"

RSpec.describe "Page views", type: :request do
  describe "GET /page_views" do
    it "lists pages busiest first with a per-country breakdown" do
      PageView.collection.insert_many([
        {"_id" => "/post/quiet", "slug" => "/post/quiet", "url" => "https://blog.example.com/post/quiet", "visitorCount" => 1, "countries" => {"US" => 1}},
        {"_id" => "/post/busy", "slug" => "/post/busy", "url" => "https://blog.example.com/post/busy", "visitorCount" => 5, "countries" => {"IN" => 3, "US" => 2}}
      ])

      get page_views_path

      expect(response).to have_http_status(:ok)
      expect(response.body.index("/post/busy")).to be < response.body.index("/post/quiet")
      expect(response.body).to include("60.0%")
      expect(response.body).to include('aria-expanded="false"')
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("tbody a[href='#{page_view_path("/post/busy")}']").text).to eq("https://blog.example.com/post/busy")
      expect(page.at_css("tbody a[href='https://blog.example.com/post/busy']")["target"]).to eq("_blank")
      expect(Nokogiri::HTML5(response.body).css("thead th").map { |th| th.text.strip }).to include("URL")
    end

    it "exports every matching page as CSV with its countries" do
      PageView.collection.insert_many([
        {"_id" => "/post/quiet", "slug" => "/post/quiet", "url" => "https://blog.example.com/post/quiet", "visitorCount" => 1, "countries" => {"US" => 1}},
        {"_id" => "/post/busy", "slug" => "/post/busy", "url" => "https://blog.example.com/post/busy", "visitorCount" => 5, "uniqueVisitorCount" => 4,
          "countries" => {"US" => 2}, "countriesByDay" => {"2026-09-01" => {"IN" => 3}}}
      ])

      get page_views_path(format: :csv, q: "busy")

      expect(response.media_type).to eq("text/csv")
      rows = CSV.parse(response.body)
      expect(rows).to eq([PageView::CSV_HEADERS, ["https://blog.example.com/post/busy", "5", "4", "0", "IN: 3; US: 2", nil, nil]])
    end

    it "counts views in a picked span from each page's days, all time staying the default" do
      PageView.collection.insert_many([
        {"_id" => "/post/old", "slug" => "/post/old", "url" => "https://blog.example.com/post/old", "visitorCount" => 900,
          "countriesByDay" => {"2026-01-01" => {"US" => 900}}},
        {"_id" => "/post/new", "slug" => "/post/new", "url" => "https://blog.example.com/post/new", "visitorCount" => 9,
          "viewsByDay" => {"2026-10-09" => 2}, "countriesByDay" => {"2026-10-10" => {"IN" => 6}, "2026-10-12" => {"IN" => 1}}}
      ])

      get page_views_path
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("[aria-controls=period-menu]").text.squish).to eq("Period: All time")
      expect(page.css("tbody tr:first-child td:nth-child(3) a").first.text).to include("/post/old")

      get page_views_path(from: "2026-10-09", to: "2026-10-11")
      page = Nokogiri::HTML5(response.body)
      rows = page.css("tbody[data-controller=disclosure] > tr:first-child").map { |row| row.css("td").map { |cell| cell.text.squish }.values_at(2, 3) }
      expect(rows).to eq([["https://blog.example.com/post/new", "8"], ["https://blog.example.com/post/old", "0"]])
      expect(page.css("thead th").map { |th| th.text.squish }).not_to include(PageView.human_attribute_name(:unique_visitor_count))
      expect(page.at_css("tbody tr[hidden]").text).to include("IN", "ZZ")
      expect(page.at_css("nav[aria-label=Period] a")["href"]).to eq(page_views_path)

      get page_views_path(format: :csv, from: "2026-10-09", to: "2026-10-11")
      expect(CSV.parse(response.body).second).to eq(["https://blog.example.com/post/new", "8", "IN: 6; ZZ: 2", nil, nil])
      expect(ExportRequest.first.filename).to eq("page-views-2026-10-09-to-2026-10-11.csv")
    end

    it "shows an empty state when there are no page views" do
      get page_views_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("No page views yet.")
    end

    context "with more pages than fit on one page" do
      # Shaped like the frontend writes them, so the page reads real data.
      before do
        PageView.collection.insert_many((1..30).map do |n|
          slug = format("/post/%02d", n)
          {"_id" => slug, "slug" => slug, "url" => "https://blog.example.com#{slug}", "visitorCount" => n, "uniqueVisitorCount" => 31 - n,
            "updatedAt" => Time.utc(2026, 9, n), "countries" => {}}
        end)
      end

      def slugs
        response.body.scan(%r{/post/\d+}).uniq
      end

      it "paginates on the server, busiest first" do
        get page_views_path(page: 2)

        expect(slugs).to eq(%w[/post/05 /post/04 /post/03 /post/02 /post/01])
        expect(response.body).to include("26–30")
      end

      it "sorts by the frontend's camelCase fields through their aliases" do
        get page_views_path(sort: "unique_visitor_count", direction: "desc")
        expect(slugs.first(2)).to eq(%w[/post/01 /post/02])
        expect(response.body).to include('aria-sort="descending"')

        get page_views_path(sort: "url", direction: "asc")
        expect(slugs.first).to eq("/post/01")

        get page_views_path(sort: "updated_at", direction: "asc")
        expect(slugs.first).to eq("/post/01")
      end

      it "searches by URL and last updated range" do
        get page_views_path(q: "post/1", updated_from: "2026-09-12", updated_to: "2026-09-13")

        expect(slugs).to eq(%w[/post/13 /post/12])
        expect(response.body).to include("URL contains “post/1”", "Last updated from 12 Sep, 2026")
      end

      it "says when nothing matches" do
        get page_views_path(q: "nothing-like-this")

        expect(response.body).to include("No page views match.")
      end
    end
  end

  describe "GET /page-views/:id" do
    it "shows a page's totals, views by day with their countries, and its breakdowns" do
      PageView.collection.insert_one(
        "_id" => "/post/busy", "slug" => "/post/busy", "url" => "https://blog.example.com/post/busy",
        "visitorCount" => 6, "uniqueVisitorCount" => 4, "botCount" => 2,
        "countries" => {"US" => 1}, "viewsByDay" => {"2026-08-30" => 1},
        "countriesByDay" => {"2026-09-01" => {"IN" => 3, "US" => 2}},
        "devices" => {"desktop" => 5, "mobile" => 1}, "referrers" => {"internal" => 6}
      )

      get page_view_path("/post/busy")

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("h1").text).to eq("/post/busy")
      expect(page.css("dl dd").map { |dd| dd.text.strip }).to eq(%w[6 4 2 2])
      days = page.css("#views-by-day ~ div tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
      expect(days).to eq([["1 Sep, 2026", "5", "IN 3 US 2"], ["30 Aug, 2026", "1", "—"]])
      expect(response.body).to include("desktop", "mobile", "internal", "83.3%")
    end

    it "breaks the period's views down by device and referrer once they're dated" do
      travel_to(Time.zone.parse("2026-10-12 12:00")) do
        PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a",
          "devices" => {"tablet" => 9}, "referrers" => {"bing_com" => 9},
          "devicesByDay" => {"2026-10-10" => {"mobile" => 3}, "2026-08-01" => {"desktop" => 7}},
          "referrersByDay" => {"2026-10-10" => {"news_ycombinator_com" => 3}, "2026-08-01" => {"direct" => 7}})

        get page_view_path("/post/a")

        page = Nokogiri::HTML5(response.body)
        devices = page.at_css("#period-devices ~ div").text
        expect(devices).to include("mobile")
        expect(devices).not_to include("tablet", "desktop")
        expect(page.at_css("#period-referrers ~ div").text).to include("news.ycombinator.com")
        expect(page.at_css("#referrers ~ div").text).to include("bing.com", "news.ycombinator.com", "direct")
        expect(response.body).not_to include("Dated from")

        get page_view_path("/post/a", from: "2026-07-01", to: "2026-10-12")

        expect(response.body).to include("Dated from 1 Aug, 2026; earlier views are only in the all-time totals below.")
      end
    end

    it "says when a page's devices and referrers aren't dated yet" do
      PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a",
        "devices" => {"tablet" => 9})

      get page_view_path("/post/a")

      expect(response.body).to include("No device data in this period.", "Not dated for this page yet; see the all-time totals below.")
    end

    it "scores the page with its search, Analytics, feed and index status over the period" do
      travel_to(Time.zone.parse("2026-10-12 12:00")) do
        PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a",
          "countriesByDay" => {"2026-10-10" => {"IN" => 3}})
        FeedEntry.create!(url: "https://blog.example.com/post/a", name: "A post", type: "tutorial",
          published_at: Time.zone.parse("2026-09-01"), last_modified_at: Time.zone.parse("2026-09-02"))
        CrawledPage.create!(url: "https://blog.example.com/post/a/", last_modified_at: Time.zone.parse("2026-09-02"), indexed: true)
        Google::SearchConsole::Stat.create!(search_type: "web", date: Date.new(2026, 10, 10), page: "https://blog.example.com/post/a",
          page_path: "/post/a", query: "a query", clicks: 2, impressions: 20, position: 3.0)
        Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/a", views: 4, engagement_seconds: 120)

        get page_view_path("/post/a")

        page = Nokogiri::HTML5(response.body)
        expect(page.at_css("#page-queries ~ div table tbody td").text).to eq("a query")
        expect(page.at_css("#page-analytics ~ ul").text.squish).to include("GA views 4", "Time per view 30s")
        expect(page.at_css("#page-status ~ ul").text.squish).to include("Tutorial: A post", "In the sitemap Yes", "Indexed Yes")
      end
    end

    it "shows the page's AI impressions from the latest upload, naming the range Google totalled them over" do
      PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a")
      get page_view_path("/post/a")
      expect(Nokogiri::HTML5(response.body).at_css("#page-ai-impressions")).to be_nil

      Google::SearchConsole::GenerativeAiRow.create!(search_type: "Web", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30),
        breakdown: "pages", label: "https://blog.example.com/post/a", impressions: 7)
      Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 9, 1), impressions: 7)
      get page_view_path("/post/a")

      expect(Nokogiri::HTML5(response.body).at_css("#page-ai-impressions").text.squish)
        .to eq("AI impressions, #{I18n.l(Date.new(2026, 9, 1))} – #{I18n.l(Date.new(2026, 9, 30))} 7")
    end

    it "sets the period's views, likes and search figures against the period before, in buckets once picked" do
      travel_to(Time.zone.parse("2026-10-12 12:00")) do
        PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a",
          "countriesByDay" => {"2026-10-10" => {"IN" => 30}, "2026-09-10" => {"IN" => 10}})

        get page_view_path("/post/a", chart_by: "week")

        card = Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=period-views]")
        expect(card.at_css("p").text.squish).to eq("Views per week 30 in the period 200.0%")
        expect(card.at_css("p span[title]")["title"]).to eq("Compared with 17 Aug, 2026 – 13 Sep, 2026")
        expect(card.at_css("select#chart-by option[selected]")["value"]).to eq("week")

        get page_view_path("/post/a", compare: "off")

        expect(Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=period-views] p").text.squish).to eq("Views per day 30 in the period")
      end
    end

    it "charts the page's clicks, impressions and position, with no data on days not synced" do
      PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a")
      [Date.new(2026, 10, 10), Date.new(2026, 10, 11)].each do |date|
        Google::SearchConsole::Stat.create!(
          search_type: "web",
          date: date,
          clicks: 9,
          impressions: 90,
          position: 5.0
        )
      end
      Google::SearchConsole::Stat.create!(
        search_type: "web",
        date: Date.new(2026, 10, 10),
        page: "https://blog.example.com/post/a",
        page_path: "/post/a",
        clicks: 2,
        impressions: 20,
        position: 3.0
      )

      get page_view_path("/post/a", from: "2026-10-09", to: "2026-10-11")

      tips = Nokogiri::HTML5(response.body).css("#page-search-trend ~ div rect[data-tip]").map do |hit|
        JSON.parse(hit["data-tip"])
      end
      expect(tips.map { |tip| tip["rows"].map { |row| row["value"] } }).to eq([
        ["No data", "No data", "No data"], %w[2 20 3.0], ["0", "0", "No data"]
      ])
    end

    it "sets the page's likes per 100 views beside the site's, once it has views enough for a rate" do
      PageView.collection.insert_many([
        {"_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a", "visitorCount" => 200},
        {"_id" => "/post/b", "slug" => "/post/b", "url" => "https://blog.example.com/post/b", "visitorCount" => 800},
        {"_id" => "/post/c", "slug" => "/post/c", "url" => "https://blog.example.com/post/c", "visitorCount" => 50}
      ])
      PageLike.collection.insert_many([{"_id" => "/post/a", "slug" => "/post/a", "likeCount" => 6}, {"_id" => "/post/b", "slug" => "/post/b", "likeCount" => 4}])

      get page_view_path("/post/a")

      bars = Nokogiri::HTML5(response.body).css("#like-rate ~ div li[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
      expect(bars.map { |bar| [bar["title"], bar["rows"].first["value"]] }).to eq([["This page", "3.0"], ["Site average", "0.95"]])

      get page_view_path("/post/c")

      expect(Nokogiri::HTML5(response.body).at_css("#like-rate").parent.text).to include("too few for a like rate")
    end

    it "shows the home page, whose id is just a slash" do
      PageView.collection.insert_one("_id" => "/", "slug" => "/", "url" => "https://blog.example.com/", "visitorCount" => 1)

      get page_view_path("/")

      expect(request.path).to eq("/page-views/%2F")
      expect(response).to have_http_status(:ok)
    end

    it "never links a stored URL that isn't http(s)" do
      PageView.collection.insert_one("_id" => "/x", "slug" => "/x", "url" => "javascript:alert(1)", "visitorCount" => 1)

      get page_view_path("/x")
      expect(response.body).to include("javascript:alert(1)")
      expect(Nokogiri::HTML5(response.body).css("a").map { |a| a["href"] }).not_to include("javascript:alert(1)")

      get page_views_path
      expect(Nokogiri::HTML5(response.body).css("a").map { |a| a["href"] }).not_to include("javascript:alert(1)")
    end

    it "is not found for an unknown page" do
      get page_view_path("/nope")
      expect(response).to have_http_status(:not_found)
    end
  end
end
