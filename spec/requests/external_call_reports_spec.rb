# encoding: UTF-8

require "rails_helper"

RSpec.describe "API health", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says so when no call was made in the period" do
    get external_call_report_path

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("No external calls in")
  end

  it "sums up each service, linking it to its calls, and lists the errors" do
    ExternalCall.create!(service: "Search Console", http_method: "POST", url: "https://example.com/", status: 403, duration_ms: 120,
      error: "the server responded with status 403", created_at: Time.zone.parse("2026-10-10 09:00"))
    ExternalCall.create!(service: "Search Console", http_method: "POST", url: "https://example.com/", status: 200, duration_ms: 80,
      created_at: Time.zone.parse("2026-10-11 09:00"))

    get external_call_report_path

    row = page.at_css("#services ~ div tbody tr")
    expect(row.css("td").map { |cell| cell.text.strip }.first(4)).to eq(["Search Console", "2", "1", "50.0%"])
    expect(row.at_css("a")["href"]).to eq(external_calls_path(service: "Search Console"))
    expect(page.at_css("#call-errors ~ div tbody").text).to include("the server responded with status 403")
  end
end
