# encoding: UTF-8

require "rails_helper"

RSpec.describe "Ranking opportunities report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says so before Search Console has synced" do
    get ranking_report_path

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

    get ranking_report_path

    cells = ->(id) { page.css("##{id} ~ div table tbody tr").map { |row| row.css("td").map { |td| td.text.squish } } }
    expect(cells.("striking-distance")).to eq([["subgrid", "—", "500", "8.0", "1.0%", "+95"]])
    expect(cells.("losing-pages")).to eq([["/post/grid", "0", "−50", "—", "—", "Fewer searches"]])
  end
end
