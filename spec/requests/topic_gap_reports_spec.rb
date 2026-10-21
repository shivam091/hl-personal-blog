# encoding: UTF-8

require "rails_helper"

RSpec.describe "Topic gaps report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says so until Search Console has synced" do
    get topic_gap_report_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#search-gaps").parent.text).to include("No Search Console figures yet.")
    expect(page.at_css("#site-search-gaps").parent.text).to include("No search came up empty")
  end

  it "groups searches no entry answers by topic, beside empty site searches" do
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 5), query: "rust lifetimes", impressions: 120, clicks: 1, position: 9.0)
    Google::SearchConsole::QueryCountryStat.create!(date: Date.new(2026, 10, 5), query: "rust lifetimes", country: "IN", impressions: 12)
    Google::Analytics::SearchTermStat.create!(date: Date.new(2026, 10, 5), search_term: "webgl", event_name: "search_no_results", event_count: 4)

    get topic_gap_report_path

    expect(page.css("#search-gaps ~ div tbody tr").map { |row| row.text.squish }).to eq(["rust · 1 query 120", "rust lifetimes No entry covers it 120 1 9.0"])
    expect(page.css("#site-search-gaps ~ div tbody td").map(&:text)).to eq(%w[webgl 4 4])

    get topic_gap_report_path(country: "IN", min_impressions: "50")
    expect(page.at_css("#search-gaps").parent.text).to include("Every query seen this often")
    expect(page.at_css("select[name=country] option[selected]").text).to include("IN")
  end

  it "exports the gaps as CSV" do
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 5), query: "rust lifetimes", impressions: 120, clicks: 1, position: 9.0)

    get topic_gap_report_path(format: :csv)

    expect(CSV.parse(response.body).second.first(4)).to eq(["rust", "rust lifetimes", "1", "120"])
  end
end
