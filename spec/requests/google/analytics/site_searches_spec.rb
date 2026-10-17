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

  it "shows no counted-from note however far back the period reaches" do
    get google_analytics_site_search_path(from: "2026-10-01", to: "2026-10-11")

    expect(page.text).not_to include("Searches are counted from")
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
      expect(page.at_css("#period-compare")).to be_present
    end

    context "with terms from the period before" do
      before do
        Google::Analytics::SearchTermStat.create!(date: Date.new(2026, 8, 17), search_term: "grid", event_name: "view_search_results", event_count: 3)
        Google::Analytics::SearchTermStat.create!(date: Date.new(2026, 8, 17), search_term: "subgrid", event_name: "search_no_results", event_count: 4)
      end

      it "shows each term's change and each tile's" do
        get google_analytics_site_search_path

        cells = ->(id) { page.css("##{id} ~ div table tbody tr").map { |row| row.css("td")[1].text.squish } }
        expect(cells.("top-terms")).to eq(["6 (+100%)", "2 (−50%)"])
        expect(cells.("not-found-terms")).to eq(["2 (−50%)"])
        expect(page.css("dl dd").map { |dd| dd.text.squish }).to include("14.3%")
      end

      it "leaves the change out when comparison is off" do
        get google_analytics_site_search_path(compare: "off")

        expect(page.css("#top-terms ~ div table tbody tr").map { |row| row.css("td")[1].text.squish }).to eq(%w[6 2])
      end

      it "puts each term's change in the CSV" do
        get google_analytics_site_search_path(format: :csv)

        expect(CSV.parse(response.body).drop(1)).to eq([["grid", "6 (+100%)", "0 (–)", "0.0"], ["subgrid", "2 (-50%)", "2 (-50%)", "1.0"]])
      end
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
