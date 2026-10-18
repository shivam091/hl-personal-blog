# encoding: UTF-8

require "rails_helper"

RSpec.describe "Google sync and export requests", type: :request do
  it "lists a ranged sync with its days, and a batch with its size" do
    SyncRequest.create!(kind: "analytics", trigger: "rake", status: "succeeded", from_date: Date.new(2026, 10, 1), to_date: Date.new(2026, 10, 7))
    SyncRequest.create!(kind: "url_inspections", limit: 100)

    get sync_requests_path

    rows = Nokogiri::HTML5(response.body).css("tbody tr").map { it.text.squish }
    expect(rows.find { it.include?("Analytics acquisition, engagement, users & retention") }).to include("Google Analytics", "1 Oct, 2026 – 7 Oct, 2026 (7 days)")
    expect(rows.find { it.include?("URL inspection") }).to include("Next 100 pages")
  end

  it "shows the last sync on every Google page a sync can be started from" do
    SyncRequest.create!(kind: "search_console_performance", status: "running")

    [google_search_console_performance_breakdown_path("pages"), google_search_console_sitemaps_path,
      google_search_console_url_inspections_path, google_analytics_acquisition_breakdown_path("sources"),
      google_analytics_engagement_breakdown_path("events"), google_analytics_users_breakdown_path("countries"),
      google_analytics_retention_breakdown_path("new-vs-returning"), google_recaptcha_stats_path].each do |path|
      get path
      expect(Nokogiri::HTML5(response.body).at_css("#last-sync")).to be_present, "no last sync on #{path}"
    end
    get google_search_console_performance_breakdown_path("pages")
    expect(Nokogiri::HTML5(response.body).at_css("#last-sync").text).to include("Sync in progress")
  end

  it "records a report's export with its breakdown and period" do
    get google_search_console_performance_breakdown_path("queries", format: :csv, export: "daily", from: "2026-10-01", to: "2026-10-07")
    get google_analytics_engagement_breakdown_path("pages", format: :csv)

    expect(ExportRequest.find_by(section: "Search performance")).to have_attributes(
      detail: "Queries, day by day, 1 Oct, 2026 – 7 Oct, 2026", filename: "search-console-queries-daily-2026-10-01-to-2026-10-07.csv"
    )
    expect(ExportRequest.find_by(section: "Analytics engagement").detail).to start_with("Events by page, ")
  end
end
