# encoding: UTF-8

require "rails_helper"

RSpec.describe "Sync health", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "lists every kind even before any sync has run" do
    get sync_health_report_path

    expect(response).to have_http_status(:ok)
    expect(page.css("#sync-kinds ~ div tbody tr").size).to eq(SyncRequest::KINDS.size)
    expect(page.at_css("#syncs-by-outcome")).to be_nil
  end

  it "puts a kind failing in a row first, linked to its runs, with its errors" do
    2.times do |day|
      started = Time.zone.parse("2026-10-1#{day} 06:00")
      SyncRequest.create!(kind: "crux", status: "failed", created_at: started, started_at: started, finished_at: started + 5,
        error_messages: ["Quota exceeded"])
    end

    get sync_health_report_path

    row = page.at_css("#sync-kinds ~ div tbody tr")
    expect(row.css("td").map { |cell| cell.text.strip }.values_at(0, 1, 2, 3)).to eq(["Web Vitals history", "2", "0%", "2 runs"])
    expect(row.at_css("a")["href"]).to eq(sync_requests_path(section: "crux"))
    expect(page.at_css("#sync-errors ~ div tbody").text).to include("Quota exceeded")
  end

  it "sets each kind and tile against the period before, and leaves the changes out with the comparison off" do
    [Time.zone.parse("2026-09-01 06:00"), Time.zone.parse("2026-10-09 06:00"), Time.zone.parse("2026-10-10 06:00")].each do |started|
      SyncRequest.create!(kind: "crux", status: "failed", created_at: started, started_at: started, finished_at: started + 5)
    end

    get sync_health_report_path

    expect(page.at_css("#period-compare")).to be_present
    expect(page.at_css("#sync-kinds ~ div tbody tr td:nth-child(2)").text).to include("(+100%)")
    expect(page.css("dl dd").map(&:text).join(" ")).to include("100.0%")

    get sync_health_report_path(compare: "off")

    expect(page.at_css("#sync-kinds ~ div tbody tr td:nth-child(2)").text).not_to include("(")
  end

  it "exports a row per kind as CSV" do
    started = Time.zone.parse("2026-10-10 06:00")
    SyncRequest.create!(kind: "crux", status: "failed", created_at: started, started_at: started, finished_at: started + 5)

    get sync_health_report_path(format: :csv)

    rows = CSV.parse(response.body)
    expect(rows.first).to eq(["Sync", "Kind", "Runs", "Succeeded", "Partial", "Failed", "Stalled", "In progress", "Median (s)", "Longest (s)",
      "Rows created or updated", "Failed in a row", "Last success"])
    expect(rows.second.first(6)).to eq(["Web Vitals history", "crux", "1", "0", "0", "1"])
    expect(rows.size).to eq(SyncRequest::KINDS.size + 1)
    expect(ExportRequest.count).to eq(1)
  end
end
