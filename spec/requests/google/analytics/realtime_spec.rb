# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics realtime", type: :request do
  let(:snapshot) { Google::Analytics::RealtimeService::Snapshot }

  it "shows who is on the blog now, by page, event, country and device" do
    allow(Google::Analytics::RealtimeService).to receive(:call) {
      snapshot.new(3, {"CSS grid" => 2, "Home" => 1}, {"page_view" => 3}, {"sign_up" => 1}, {"IN" => 3}, {"Pune" => 3},
        {"mobile" => 3}, {"web" => 3}, 29.downto(0).to_h { |ago| [Time.zone.local(2026, 10, 31, 9, 30) - ago.minutes, ago.zero? ? 3 : 0] }, [])
    }

    get google_analytics_realtime_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("dl dd").text.strip).to eq("3")
    expect(page.at_css("#pages + div").text).to include("CSS grid")
    expect(page.at_css("#events + div").text).to include("page_view")
    expect(page.at_css("#key-events + div").text).to include("sign_up")
    expect(page.at_css("#cities + div").text).to include("Pune")
    chart = page.at_css("#per-minute + div")
    expect(chart.at_css("ul").text.strip).to eq("Active users")
    expect(chart.text).to include("Active users", "Time", "09:06", "09:30")
    expect(page.at_css("[data-controller=auto-refresh]")["data-auto-refresh-interval-value"]).to eq("60")
    expect(page.at_css("#countries + div").text).to include("🇮🇳 IN")
    expect(page.css("dl dt").map { |label| label.text.strip.lines.first.strip }).to eq(
      ["Active users", "Views", "Event count", "Key events", "Pages", "Countries", "Cities", "Devices"]
    )
    expect(page.css("dl dd").map { |value| value.text.strip }.values_at(1, 2, 3)).to eq(%w[3 3 1])
  end

  it "says why when Analytics can't be read" do
    allow(Google::Analytics::RealtimeService).to receive(:call) {
      snapshot.new(0, *Array.new(8) { {} }, ["No Analytics property configured (credentials google.analytics_property_id)"])
    }

    get google_analytics_realtime_path

    expect(Nokogiri::HTML5(response.body).at_css("[role=alert]").text).to include("No Analytics property configured")
  end
end
