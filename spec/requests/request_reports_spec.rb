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

    day = page.css("#requests-by-status ~ div g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.find { |tip| tip["title"] == "Sat, 10 Oct 2026" }
    expect(day["rows"].map { |row| [row["name"], row["value"]] }).to include(["2xx", "1"])
    expect(page.css("#slowest-paths ~ div tbody td:first-child").map(&:text)).to include("/crawled-pages", "/")
    expect(page.at_css("#exceptions ~ div a")["href"]).to eq(request_log_path(failed.id))
    expect(page.css("#request-hours ~ div td div[data-tip]").size).to eq(7 * 24)
  end
end
