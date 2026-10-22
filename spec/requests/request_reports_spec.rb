# encoding: UTF-8

require "rails_helper"

RSpec.describe "Request report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  def log(at, **attributes)
    RequestLog.create!(uri: "https://admin.example.com/", request_method: "GET", status: 200, created_at: Time.zone.parse(at), **attributes)
  end

  before { RequestLog.delete_all }

  it "says so when nothing was logged in the period" do
    get request_report_path

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("No requests logged in")
  end

  it "charts requests by status, times them and links each exception to its latest log" do
    log("2026-10-10 09:15", elapsed_time: 0.25)
    failed = log("2026-10-11 22:05", uri: "https://admin.example.com/crawled-pages", status: 500,
      exception: {"class" => "Mongo::Error::SocketError", "message" => "timed out"})

    get request_report_path

    day = page.css("section[aria-labelledby=requests-by-status] g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.find { |tip| tip["rows"].first["period"] == "Sat, 10 Oct 2026" }
    expect(day["rows"].map { |row| [row["name"], row["value"]] }).to include(["2xx", "1"])
    expect(page.css("#slowest-paths ~ div tbody td:first-child").map(&:text)).to include("/crawled-pages", "/")
    expect(page.at_css("#exceptions ~ div a")["href"]).to eq(request_log_path(failed.id))
    expect(page.css("#request-hours ~ div td div[data-tip]").size).to eq(7 * 24)
  end

  it "offers the compare menu and sets each figure and page against the period before" do
    log("2026-09-01 09:00", elapsed_time: 0.1, ip_info: {"country_code" => "IN"})
    2.times { log("2026-10-10 09:15", elapsed_time: 0.25, ip_info: {"country_code" => "IN"}) }

    get request_report_path

    expect(page.at_css("#period-compare")).to be_present
    expect(page.css("dl dd").map(&:text).join(" ")).to include("100.0%")
    expect(page.at_css("#slowest-paths ~ div tbody tr").text).to include("(+100%)", "(+150%)")
    expect(page.css("[aria-labelledby=request-countries] path[class*=stroke-emerald-600], [aria-labelledby=request-countries] path[class*=stroke-red-600]")).to be_present
  end

  it "shows no changes with the comparison off" do
    log("2026-09-01 09:00", elapsed_time: 0.1, ip_info: {"country_code" => "IN"})
    log("2026-10-10 09:15", elapsed_time: 0.25, ip_info: {"country_code" => "IN"})

    get request_report_path(compare: "off")

    expect(page.css("dl dd").map(&:text).join(" ")).not_to include("(+")
    expect(page.at_css("#slowest-paths ~ div tbody tr").text).not_to include("(")
    expect(page.css("[aria-labelledby=request-countries] path[class*=stroke-emerald-600], [aria-labelledby=request-countries] path[class*=stroke-red-600]")).to be_empty
  end

  it "sets each page's counts against the period before in the CSV" do
    log("2026-09-01 09:00", elapsed_time: 0.1)
    2.times { log("2026-10-10 09:15", elapsed_time: 0.25) }

    get request_report_path(format: :csv)

    expect(CSV.parse(response.body).last).to eq(["/", "2 (+100%)", "250 (+150%)", "250 (+150%)", "250 (+150%)", "0 (–)"])
  end

  it "exports a row per page as CSV" do
    log("2026-10-10 09:15", elapsed_time: 0.25)

    get request_report_path(format: :csv)

    expect(CSV.parse(response.body)).to eq([
      ["Path", "Requests", "Median (ms)", "95th percentile (ms)", "Slowest (ms)", "Server errors"],
      ["/", "1", "250", "250", "250", "0"]
    ])
    expect(ExportRequest.count).to eq(1)
  end
end
