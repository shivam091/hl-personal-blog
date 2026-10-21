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
    expect(rows.second).to eq(["IN", "200", "4", "0.02", "0", "0.0", "0", nil, nil])
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
    expect(Nokogiri::HTML5(response.body).at_css("#country-table tbody tr").css("td")[7].text).to eq("9")
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
