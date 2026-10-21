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
    # The site's are its countries' added up: 108 elsewhere and 12 in India.
    search_console_row(date: Date.new(2026, 10, 5), impressions: 120, clicks: 1, position: 9.0)
    search_console_row(date: Date.new(2026, 10, 5), query: "rust lifetimes", impressions: 108, clicks: 1, position: 9.0)
    Google::SearchConsole::QueryCountryStat.create!(date: Date.new(2026, 10, 5), query: "rust lifetimes", country: "IN", impressions: 12, position: 9.0)
    Google::Analytics::SearchTermStat.create!(date: Date.new(2026, 10, 5), search_term: "webgl", event_name: "search_no_results", event_count: 4)

    get topic_gap_report_path

    expect(page.css("#search-gaps ~ div tbody tr").map { |row| row.text.squish }).to eq(["rust · 1 query 120", "rust lifetimes No entry covers it 120 1 9.0"])
    expect(page.css("#site-search-gaps ~ div tbody td").map { |cell| cell.text.squish }).to eq(%w[webgl 4 4])

    get topic_gap_report_path(country: "IN", min_impressions: "50")
    expect(page.at_css("#search-gaps").parent.text).to include("Every query seen this often")
    expect(page.at_css("select[name=country] option[selected]").text).to include("IN")
  end

  it "sets each query against the period before, and leaves the changes out with the comparison off" do
    # Synced before the days compared with, which is what lets the change be trusted.
    search_console_row(date: Date.new(2026, 8, 1), impressions: 5, clicks: 0, position: 20.0)
    search_console_row(date: Date.new(2026, 8, 1), query: "unrelated", impressions: 5, clicks: 0, position: 20.0)
    search_console_row(date: Date.new(2026, 9, 1), query: "rust lifetimes", impressions: 60, clicks: 1, position: 12.0)
    search_console_row(date: Date.new(2026, 10, 5), query: "rust lifetimes", impressions: 120, clicks: 1, position: 9.0)

    get topic_gap_report_path

    expect(page.at_css("#period-compare")).to be_present
    expect(page.css("#search-gaps ~ div tbody tr").last.text.squish).to include("120 (+100%)")

    get topic_gap_report_path(compare: "off")

    expect(page.css("#search-gaps ~ div tbody tr").last.text).not_to include("(+")
  end

  it "exports the gaps as CSV" do
    search_console_row(date: Date.new(2026, 10, 5), query: "rust lifetimes", impressions: 120, clicks: 1, position: 9.0)

    get topic_gap_report_path(format: :csv)

    expect(CSV.parse(response.body).second.first(4)).to eq(["rust", "rust lifetimes", "1", "120"])
  end
end
