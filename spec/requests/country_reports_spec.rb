# encoding: UTF-8

require "rails_helper"

RSpec.describe "Country report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  before do
    PageView.collection.insert_one(
      "_id" => "/post/a",
      "slug" => "/post/a",
      "countriesByDay" => {"2026-10-10" => {"IN" => 200, "US" => 40, "DE" => 120}}
    )
    PageLike.collection.insert_one(
      "_id" => "/post/a",
      "slug" => "/post/a",
      "likeCount" => 13,
      "countriesByDay" => {"2026-10-10" => {"IN" => 4, "DE" => 9}}
    )
  end

  def countries
    Nokogiri::HTML5(response.body).css("#country-table tbody tr td:first-child").map do |td|
      td.text.squish
    end
  end

  it "reads a country with no activity as zero in the map's tooltip, like one with some" do
    get country_report_path

    page = Nokogiri::HTML5(response.body)
    tip = ->(title) { JSON.parse(page.css("section[aria-labelledby=country-map] svg path[data-tip]").map { |path| path["data-tip"] }.find { |data| data.include?(title) })["rows"].map { |row| [row["name"], row["value"]] } }
    expect(tip.("Brazil").map(&:first)).to eq(tip.("India").map(&:first))
    expect(tip.("Brazil")).to include(["Likes", "0"], ["Subscribers", "0"], ["Messages", "0"])
  end

  it "shows each country's AI impressions from the latest upload, once there is one" do
    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 9, 1), impressions: 9)
    Google::SearchConsole::GenerativeAiRow.create!(search_type: "Web", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30),
      breakdown: "countries", label: "India", country: "IN", impressions: 9)

    get country_report_path

    page = Nokogiri::HTML5(response.body)
    column = page.css("#country-table thead th").map { |th| th.text.squish }.index("AI impressions")
    expect(page.css("#country-table tbody tr").map { |row| [row.css("td").first.text.squish, row.css("td")[column].text.squish] })
      .to eq([["🇮🇳 IN", "9"], ["🇩🇪 DE", "0"], ["🇺🇸 US", "0"]])

    get country_report_path(format: :csv)
    csv = CSV.parse(response.body, headers: true)
    expect(csv.map { |row| [row["Country"], row["AI impressions 2026-09-01 to 2026-09-30"]] }).to eq([%w[IN 9], %w[DE 0], %w[US 0]])
  end

  it "sets each country's search clicks and GA views against the period before, and leaves them out with the comparison off" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {"countriesByDay.2026-09-01" => {"IN" => 20}}})
    Google::SearchConsole::Stat.create!(search_type: "web", page: "https://example.com/post/a", page_path: "/post/a", date: Date.new(2026, 8, 1))
    [[Date.new(2026, 10, 10), 10], [Date.new(2026, 9, 1), 5]].each do |date, clicks|
      Google::SearchConsole::CountryStat.create!(search_type: "web", date: date, country: "IN", clicks: clicks, impressions: 20)
      Google::Analytics::CountryStat.create!(date: date, page_path: "/post/a", country: "IN", views: clicks * 2)
    end
    Google::Analytics::Stat.create!(date: Date.new(2026, 8, 1), page_path: "/post/a", views: 1)

    get country_report_path

    page = Nokogiri::HTML5(response.body)
    headings = page.css("#country-table thead th").map { |th| th.text.squish }
    cells = page.css("#country-table tbody tr:first-child td").map { |td| td.text.squish }
    expect(cells[headings.index("Search clicks")]).to include("10", "+100%")
    expect(cells[headings.index("GA views")]).to include("20", "+100%")

    get country_report_path(compare: "off")

    cells = Nokogiri::HTML5(response.body).css("#country-table tbody tr:first-child td").map { |td| td.text.squish }
    expect(cells[headings.index("Search clicks")]).to eq("10")
  end

  it "lists every country busiest first" do
    get country_report_path

    expect(response).to have_http_status(:ok)
    expect(countries).to eq(["🇮🇳 IN", "🇩🇪 DE", "🇺🇸 US"])
    expect(response.body).to include("7.5%")
  end

  it "sorts by a rate, leaving countries with too few views last" do
    get country_report_path(sort: "like_rate", direction: "desc")

    expect(countries).to eq(["🇩🇪 DE", "🇮🇳 IN", "🇺🇸 US"])
  end

  it "narrows to the chosen country" do
    get country_report_path(country: "DE")

    expect(countries).to eq(["🇩🇪 DE"])
  end

  it "exports the rows as CSV" do
    get country_report_path(format: :csv)

    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body)
    expect(rows.first).to eq(BlogStats::FUNNEL_CSV_HEADERS)
    expect(rows.second).to eq(["IN", "200 (new)", "4 (new)", "0.02", "0 (–)", "0.0", "0 (–)", nil, nil])
    expect(ExportRequest.count).to eq(1)
  end

  it "adds Google's columns once they've synced" do
    Google::SearchConsole::Stat.create!(
      search_type: "web",
      date: Date.new(2026, 10, 10),
      clicks: 1,
      impressions: 1
    )
    Google::SearchConsole::CountryStat.create!(
      search_type: "web",
      date: Date.new(2026, 10, 10),
      country: "IN",
      clicks: 9,
      impressions: 20
    )

    get country_report_path

    headings = Nokogiri::HTML5(response.body).css("#country-table thead th").map { |th| th.text.strip }
    expect(headings).to include("Search clicks")
    expect(headings).not_to include("GA views")
    expect(Nokogiri::HTML5(response.body).at_css("#country-table tbody tr").css("td")[7].text.squish).to eq("9")
  end

  it "shows each country's change against the period before, or against the compared country" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {"countriesByDay.2026-09-10" => {"IN" => 100}}})

    get country_report_path
    india = Nokogiri::HTML5(response.body).at_css("#country-table tbody tr")
    expect(india.css("td")[1].text.squish).to eq("200 (+100%)")

    get country_report_path(compare: "country", vs: "US", country: "DE")
    germany = Nokogiri::HTML5(response.body).at_css("#country-table tbody tr")
    expect(germany.css("td")[1].text.squish).to eq("120 (+200%)")
    expect(germany.css("td")[1].at_css("span[title]")["title"]).to include("in", "US")

    get country_report_path(compare: "off")
    expect(Nokogiri::HTML5(response.body).at_css("#country-table tbody tr").css("td")[1].text.squish).to eq("200")
  end
end
