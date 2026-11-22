# encoding: UTF-8

require "rails_helper"

RSpec.describe "Consent page gaps", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  it "says so until GA has synced" do
    get consent_page_gap_report_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("GA hasn&#39;t synced yet")
  end

  context "with views on both sides" do
    before do
      %w[/a /b /c /d /e].each do |slug|
        PageView.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => {"2026-10-10" => {"IN" => 100}})
        Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: slug, views: 80)
      end
      PageView.collection.insert_one("_id" => "/broken", "slug" => "/broken", "countriesByDay" => {"2026-10-10" => {"IN" => 100}})
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/broken/", views: 10)
    end

    it "lists each page with its gap and flags the page losing most" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      page = Nokogiri::HTML5(response.body)
      row = page.css("#page-gap-table tbody tr").find { |tr| tr.text.include?("/broken") }
      expect(row.text.squish).to include("100", "10", "90", "90.0%", "Well above the median")
      expect(page.text.squish).to include("1 page flagged")
    end

    it "sorts by a column asked for" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12", sort: "gap", direction: "asc")

      slugs = Nokogiri::HTML5(response.body).css("#page-gap-table tbody tr td:first-child").map { |cell| cell.text.strip }
      expect(slugs.last).to eq("/broken")
    end

    it "exports the table as CSV" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12", format: :csv)

      expect(response.media_type).to eq("text/csv")
      expect(CSV.parse(response.body, headers: true).map { |row| row["Page"] }).to include("/broken")
    end
  end
end
