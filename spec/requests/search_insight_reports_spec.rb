# encoding: UTF-8

require "rails_helper"

RSpec.describe "Search insights report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  def gsc(**attributes)
    Google::SearchConsole::Stat.create!(search_type: "web", date: Date.new(2026, 10, 10), **attributes)
  end

  before do
    gsc(clicks: 40, impressions: 1000, position: 7.0)
    gsc(query: "css grid", clicks: 3, impressions: 400, position: 8.0)
    gsc(query: "git rebase", clicks: 30, impressions: 300, position: 2.0)
    gsc(page: "https://blog.example.com/post/a", page_path: "/post/a", clicks: 1, impressions: 500, position: 9.0)
    Google::SearchConsole::CountryStat.create!(
      search_type: "web",
      date: Date.new(2026, 10, 10),
      country: "IN",
      clicks: 25,
      impressions: 600
    )
  end

  it "shows totals, top queries, quick wins and pages to retitle" do
    get search_insight_report_path

    expect(response).to have_http_status(:ok)
    expect(page.css("#top-queries ~ div tbody tr td:first-child").map(&:text)).to eq(["git rebase", "css grid"])
    expect(page.css("#opportunities ~ div table tbody td:first-child").map(&:text)).to eq(["css grid"])
    expect(page.css("#low-ctr-pages ~ div table tbody td:first-child").map { |td| td.text.strip }).to eq(["/post/a"])
    expect(page.at_css("#search-countries ~ div").text).to include("IN")
  end

  it "lists top and trending pages and queries as Search Console's Insights does, pages named after their posts" do
    FeedEntry.create!(url: "https://blog.example.com/post/a", name: "Post A", type: "post",
      published_at: Time.utc(2026, 10, 1), last_modified_at: Time.utc(2026, 10, 1))

    get search_insight_report_path

    content = page.at_css("#your-content-panel-top")
    expect(content.text).to include("Post A")
    expect(content.css("li").size).to eq(1)
    queries = page.css("#queries-to-site-panel-top li p:first-child").map { |p| p.text.strip }
    expect(queries).to eq(["git rebase", "css grid"])
    expect(page.at_css("#queries-to-site-panel-up").text).to include("No earlier figures to compare with yet.")
    expect(page.at_css("#queries-to-site-panel-up")["hidden"]).not_to be_nil
  end

  it "totals the search types other than web" do
    gsc(search_type: "image", clicks: 2, impressions: 90, position: 4.0)

    get search_insight_report_path

    expect(page.css("#search-types ~ table tbody tr").map { |tr| tr.css("td").map { |td| td.text.strip } }).to eq([["Image", "2", "90"]])
  end

  it "charts the share of search impressions from AI answers for the whole site only" do
    get search_insight_report_path
    expect(page.at_css("#ai-share")).to be_nil

    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 10, 10), impressions: 50)
    get search_insight_report_path

    card = page.at_css("section[aria-labelledby=ai-share]")
    expect(card.css("[data-tip]")).not_to be_empty
    expect(card.text.squish).to include("50 AI impressions (Web), 5.0% of the period's 1,000 search impressions.")

    get search_insight_report_path(country: "IN")
    expect(page.at_css("#ai-share")).to be_nil
  end

  it "sets the AI share against the period before, and leaves it out with the comparison off" do
    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 10, 10), impressions: 50)
    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 8, 17), impressions: 10)
    Google::SearchConsole::Stat.create!(search_type: "web", date: Date.new(2026, 8, 17), clicks: 5, impressions: 500, position: 7.0)

    get search_insight_report_path

    card = page.at_css("section[aria-labelledby=ai-share]")
    expect(card.text.squish).to include("Against 2.0% in", "(10 of 500)", "150")

    get search_insight_report_path(compare: "off")
    expect(page.at_css("section[aria-labelledby=ai-share]").text).not_to include("Against")
  end

  it "splits queries into branded and non-branded" do
    gsc(query: "harshal ladhe", clicks: 2, impressions: 4, position: 1.0)

    get search_insight_report_path

    rows = page.css("section[aria-labelledby=branded] tbody tr").map { |row| row.css("td").map { |cell| cell.text.strip }.first(4) }
    expect(rows).to eq([["Branded", "1", "2", "5.7%"], ["Non-branded", "2", "33", "94.3%"]])
  end

  it "groups queries by why people searched" do
    gsc(query: "css grid vs flexbox", clicks: 1, impressions: 50, position: 6.0)

    get search_insight_report_path

    bar = JSON.parse(page.css("#intent ~ div li[data-tip]")[1]["data-tip"])
    expect([bar["title"], bar["rows"].first["value"]]).to eq(["Comparison", "50"])
    expect(page.at_css("#intent").parent.at_css("dl").text.squish).to include("Comparison css grid vs flexbox", "Topic css grid, git rebase")
  end

  it "shows how long since Google crawled each page and which changed after" do
    page_a = CrawledPage.create!(url: "https://blog.example.com/post/a", last_modified_at: Time.zone.parse("2026-10-05"))
    Google::SearchConsole::UrlInspection.create!(crawled_page: page_a, last_crawled_at: Time.zone.parse("2026-09-01"))

    get search_insight_report_path

    bucket = JSON.parse(page.css("#crawl-ages ~ div li[data-tip]")[2]["data-tip"])
    expect([bucket["title"], bucket["rows"].first["value"]]).to eq(["1–3 months", "1"])
    expect(page.css("#changed-since-crawl ~ div tbody td").map { |cell| cell.text.strip }).to eq(["/post/a", "1 Sep, 2026", "5 Oct, 2026"])
  end

  it "lists queries new to the period and those it lost" do
    get search_insight_report_path
    expect(page.at_css("#new-queries").parent.text).to include("don't reach back to")

    previous = ->(day, **attributes) {
      Google::SearchConsole::Stat.create!(search_type: "web", date: Date.new(2026, 8, day), **attributes)
    }
    previous.(17, clicks: 5, impressions: 100)
    previous.(20, query: "git rebase", clicks: 4, impressions: 50, position: 3.0)
    previous.(20, query: "flexbox", clicks: 2, impressions: 80, position: 6.0)

    get search_insight_report_path
    expect(page.css("#new-queries ~ div tbody td:first-child").map(&:text)).to eq(["css grid"])
    expect(page.css("#lost-queries ~ div tbody td:first-child").map(&:text)).to eq(["flexbox"])

    get search_insight_report_path(format: :csv, export: "lost")
    expect(CSV.parse(response.body)).to eq([
      ["Query", "Clicks", "Impressions", "CTR", "Position"],
      ["flexbox", "2", "80", "0.025", "6.0"]
    ])
  end

  it "measures the charts and breakdowns against the comparison, and nothing at all with No comparison" do
    before = ->(model = Google::SearchConsole::Stat, **attributes) { model.create!(search_type: "web", date: Date.new(2026, 8, 17), **attributes) }
    before.(clicks: 20, impressions: 500, position: 9.0)
    before.(query: "css grid", clicks: 1, impressions: 100, position: 6.0)
    before.(search_type: "image", clicks: 1, impressions: 40, position: 5.0)
    before.(Google::SearchConsole::CountryStat, country: "IN", clicks: 5, impressions: 100)
    before.(Google::SearchConsole::DeviceStat, device: "DESKTOP", clicks: 5, impressions: 100)
    before.(Google::SearchConsole::AppearanceStat, appearance: "VIDEO", clicks: 4, impressions: 10)
    before.(date: Date.new(2026, 8, 22), clicks: 20, impressions: 400, position: 9.0)
    Google::SearchConsole::AppearanceStat.create!(search_type: "web", date: Date.new(2026, 10, 10), appearance: "VIDEO", clicks: 6, impressions: 20)
    gsc(search_type: "image", clicks: 2, impressions: 90, position: 4.0)
    Google::SearchConsole::DeviceStat.create!(search_type: "web", date: Date.new(2026, 10, 10), device: "DESKTOP", clicks: 10, impressions: 200)
    card = ->(id) { page.at_css("section[aria-labelledby=#{id}]").text.squish }

    get search_insight_report_path
    expect(card.("clicks")).to include("Clicks, ")
    expect(card.("impressions")).to include("Impressions, ")
    expect(card.("appearances")).to include("Clicks, ")
    expect(card.("top-queries")).to include("3 (+200%)", "400 (+300%)")
    expect(card.("weekday-clicks")).to include("(+110%)")
    expect(card.("search-countries")).to include("25 (+400%)")
    expect(card.("search-devices")).to include("10 (+100%)")
    expect(card.("search-types")).to include("2 (+100%)")
    expect(card.("positions")).to include("1 (0%)")
    expect(card.("branded")).to include("(+3200%)")
    expect(card.("intent")).to include("(+")
    expect(page.at_css("#top-queries").parent.css("th").map(&:text)).to include("Change")

    get search_insight_report_path(compare: "off")
    %w[clicks impressions appearances weekday-clicks top-queries search-countries search-devices search-types positions branded intent].each do |id|
      expect(card.(id)).not_to match(/, \d|\([+−–0]/)
    end
    expect(page.at_css("#top-queries").parent.css("th").map(&:text)).not_to include("Change")
    expect(card.("new-queries")).to include("Pick a comparison in the Compare menu to see these.")
    expect(card.("queries-to-site")).to include("Pick a comparison in the Compare menu to see what's trending.")
    expect(page.at_css("#your-content-panel-top li").text).not_to include("Previously")
  end

  it "compares totals and queries with another country over the same dates" do
    Google::SearchConsole::CountryStat.create!(
      search_type: "web",
      date: Date.new(2026, 10, 10),
      country: "US",
      clicks: 5,
      impressions: 100
    )
    crossed = ->(**attributes) { Google::SearchConsole::QueryCountryStat.create!(search_type: "web", date: Date.new(2026, 10, 10), **attributes) }
    crossed.(query: "css grid", country: "IN", clicks: 3, impressions: 300, position: 6.0)
    crossed.(query: "git rebase", country: "IN", clicks: 9, impressions: 90, position: 2.0)
    crossed.(query: "css grid", country: "US", clicks: 1, impressions: 50, position: 9.0)
    crossed.(query: "flexbox", country: "US", clicks: 1, impressions: 20, position: 4.0)

    get search_insight_report_path(country: "IN", compare: "country", vs: "US")
    expect(page.at_css("dl dd[title='Compared with US']").text.squish).to eq("400.0%")
    expect(page.css("#new-queries ~ div tbody td:first-child").map(&:text)).to eq(["git rebase"])
    expect(page.css("#lost-queries ~ div tbody td:first-child").map(&:text)).to eq(["flexbox"])
    expect(page.css("#top-queries ~ div tbody tr td:first-child").map(&:text)).to eq(["git rebase", "css grid"])
  end

  it "says which figures follow the country filter" do
    get search_insight_report_path(country: "IN")

    expect(response.body).to include("Totals, charts and queries are for")
  end

  it "exports each list as CSV" do
    get search_insight_report_path(format: :csv, export: "opportunities")

    expect(CSV.parse(response.body)).to eq([
      ["Query", "Clicks", "Impressions", "CTR", "Position", "Position before"],
      ["css grid", "3", "400", "0.0075", "8.0", nil]
    ])
  end

  it "stacks each day's clicks by search appearance, the busiest few named and the rest together" do
    %w[VIDEO REVIEW_SNIPPET FAQ_RICH_RESULT BREADCRUMB AMP_BLUE_LINK].each_with_index do |appearance, index|
      Google::SearchConsole::AppearanceStat.create!(
        search_type: "web",
        date: Date.new(2026, 10, 10),
        appearance: appearance,
        clicks: 10 - index,
        impressions: 100
      )
    end

    get search_insight_report_path

    card = page.at_css("section[aria-labelledby=appearances]")
    expect(card.css("ul li").map(&:text)).to eq([
      "Video", "Review snippet", "Faq rich result", "Breadcrumb", "Other"
    ])
    day = card.css("g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.find do |tip|
      tip["title"] == "Sat, 10 Oct 2026"
    end
    expect(day["rows"].map { |row| row["value"] }).to eq(%w[10 9 8 7 6])
  end

  it "puts each day's clicks in a grid of weekdays by week, with each weekday's average" do
    get search_insight_report_path

    cell = page.css("#weekday-clicks ~ div [data-tip]").find { |hit| JSON.parse(hit["data-tip"])["title"] == "Sat, 10 Oct 2026" }
    expect(cell.text).to eq("40")
    expect(page.css("#weekday-clicks ~ div thead th").last.text).to eq("Avg")
    saturday = page.css("#weekday-clicks ~ div tbody tr").find { |row| row.at_css("th").text == "Sat" }
    expect(saturday.css("td").last.text).to eq("40.0")
  end

  it "plots each query's CTR against the site's usual CTR for its position, flagging those well under it" do
    gsc(query: "flexbox", clicks: 100, impressions: 1000, position: 3.0)
    gsc(query: "subgrid", clicks: 10, impressions: 1000, position: 3.2)

    get search_insight_report_path

    tips = page.css("#ctr-position ~ div [data-tip]").map { |dot| JSON.parse(dot["data-tip"]) }
    expect(tips.map { |tip| tip["title"] }).to contain_exactly("css grid", "git rebase", "flexbox", "subgrid")
    expect(page.css("#ctr-position ~ div polyline")).to be_present
    expect(page.css("#ctr-position ~ div table tbody td:first-child").map(&:text)).to eq(["subgrid"])

    get search_insight_report_path(format: :csv, export: "ctr")
    rows = CSV.parse(response.body, headers: true)
    expect(rows.to_h { |row| [row["Query"], row["Well under usual"]] }).to eq(
      "flexbox" => "No", "subgrid" => "Yes", "css grid" => "No", "git rebase" => "No"
    )
  end

  it "lists queries two or more pages each take a real share of, leaving out stray pages" do
    competing = ->(path, impressions, position) {
      gsc(
        query: "flexbox",
        page: "https://blog.example.com#{path}",
        page_path: path,
        clicks: 1,
        impressions: impressions,
        position: position
      )
    }
    competing.("/post/a", 300, 4.0)
    competing.("/post/b", 200, 9.0)
    competing.("/post/c", 10, 30.0)

    get search_insight_report_path

    row = page.at_css("#competing-pages ~ div tbody tr")
    expect(row.at_css("td").text).to eq("flexbox")
    expect(row.css("li a:not([target=_blank])").map(&:text)).to eq(["/post/a", "/post/b"])
    expect(row.css("li").first.text).to include("58.82%", "position 4.0")

    get search_insight_report_path(format: :csv, export: "competing")
    expect(CSV.parse(response.body)).to eq([
      ["Query", "Page", "Clicks", "Impressions", "Share of query's impressions", "Position"],
      ["flexbox", "/post/a", "1", "300", "0.5882", "4.0"], ["flexbox", "/post/b", "1", "200", "0.3922", "9.0"]
    ])
  end

  it "shows an empty state before the first sync" do
    Google::SearchConsole::Stat.delete_all

    get search_insight_report_path
    expect(response.body).to include("No Search Console figures yet.")
  end
end
