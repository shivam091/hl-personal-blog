# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics site search", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says so before any search terms have synced" do
    get google_analytics_site_search_path

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("No search terms yet.")
  end

  it "says from when searches count, while the period reaches back past it" do
    get google_analytics_site_search_path(from: "2026-10-01", to: "2026-10-11")
    expect(page.at_css("[role=status]").text).to include("Searches only count from 20 Oct 2026")

    get google_analytics_site_search_path(from: "2026-10-20", to: "2026-10-23")
    expect(page.text).not_to include("Searches only count from")
  end

  context "with search terms" do
    before do
      Google::Analytics::SearchTermStat.create!(
        date: Date.new(2026, 10, 8),
        search_term: "grid",
        event_name: "view_search_results",
        event_count: 6
      )
      Google::Analytics::SearchTermStat.create!(
        date: Date.new(2026, 10, 8),
        search_term: "subgrid",
        event_name: "search_no_results",
        event_count: 2
      )
    end

    it "lists top terms and the ones that found nothing" do
      get google_analytics_site_search_path

      cells = ->(id) { page.css("##{id} ~ div table tbody tr").map { |row| row.css("td").map { |td| td.text.strip } } }
      expect(cells.("top-terms")).to eq([["grid", "6", "0.0%"], ["subgrid", "2", "100.0%"]])
      expect(cells.("not-found-terms")).to eq([["subgrid", "2"]])
      # The terms are only ever read for one period.
      expect(page.at_css("#period-compare")).to be_nil
    end

    it "exports every term as CSV" do
      get google_analytics_site_search_path(format: :csv)

      expect(CSV.parse(response.body)).to eq([
        ["Search term", "Searches", "Found nothing", "Share found nothing"],
        ["grid", "6", "0", "0.0"], ["subgrid", "2", "2", "1.0"]
      ])
    end
  end
end
