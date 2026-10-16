# encoding: UTF-8

require "rails_helper"

RSpec.describe "Ranking opportunities report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says so before Search Console has synced" do
    get ranking_opportunity_report_path

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("No Search Console figures yet.")
  end

  it "lists striking-distance queries and pages losing clicks" do
    Google::SearchConsole::Stat.create!(
      date: Date.new(2026, 8, 1),
      clicks: 1,
      impressions: 1
    )
    Google::SearchConsole::Stat.create!(
      date: Date.new(2026, 10, 1),
      query: "css grid",
      position: 3.0,
      impressions: 200,
      clicks: 40
    )
    Google::SearchConsole::Stat.create!(
      date: Date.new(2026, 10, 1),
      query: "subgrid",
      position: 8.0,
      impressions: 500,
      clicks: 5
    )
    Google::SearchConsole::Stat.create!(
      date: Date.new(2026, 9, 1),
      page: "https://blog.example.com/post/grid",
      page_path: "/post/grid",
      clicks: 50,
      impressions: 1000,
      position: 3.0
    )

    get ranking_opportunity_report_path

    cells = ->(id) { page.css("##{id} ~ div table tbody tr").map { |row| row.css("td").map { |td| td.text.squish } } }
    expect(cells.("striking-distance")).to eq([["subgrid", "—", "500 (new)", "8.0 New", "1.0%", "+95"]])
    expect(cells.("losing-pages")).to eq([["/post/grid", "0", "−50", "—", "—", "Fewer searches"]])
  end

  it "leaves out what losing pages are judged against, and every change, with No comparison" do
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 8, 1), clicks: 1, impressions: 1)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 1), query: "css grid", position: 3.0, impressions: 200, clicks: 40)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 1), query: "subgrid", position: 8.0, impressions: 500, clicks: 5)

    get ranking_opportunity_report_path(compare: "off")

    cells = ->(id) { page.css("##{id} ~ div table tbody tr").map { |row| row.css("td").map { |td| td.text.squish } } }
    expect(cells.("striking-distance")).to eq([["subgrid", "—", "500", "8.0", "1.0%", "+95"]])
    expect(page.at_css("#losing-pages").parent.text).to include("shows once a comparison is picked")
    expect(cells.("losing-pages")).to be_empty
  end

  it "narrows queries to a country, leaving pages, which aren't split by country, every country's" do
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 1), query: "subgrid", position: 8.0, impressions: 500, clicks: 5)
    Google::SearchConsole::QueryCountryStat.create!(date: Date.new(2026, 10, 1), query: "grid gap", country: "IN", position: 9.0, impressions: 300, clicks: 3)

    get ranking_opportunity_report_path(country: "IN")

    expect(page.css("#striking-distance ~ div table tbody td:first-child").map(&:text)).to eq(["grid gap"])
    expect(page.at_css("#losing-pages").parent.text).to include("Every country")
    expect(page.at_css("a[href*='.csv'][href*='country=IN']")).to be_present

    get ranking_opportunity_report_path(country: "IN", compare: "country", vs: "US")

    expect(page.at_css("#losing-pages").parent.text).to include("doesn't split pages by country")
  end
end
