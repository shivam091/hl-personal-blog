# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics realtime", type: :request do
  let(:snapshot) { Google::Analytics::RealtimeService::Snapshot }

  it "shows who is on the blog now, by page, country and device" do
    allow(Google::Analytics::RealtimeService).to receive(:call) {
      snapshot.new(3, {"CSS grid" => 2, "Home" => 1}, {"IN" => 3}, {"mobile" => 3}, [])
    }

    get google_analytics_realtime_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("dl dd").text.strip).to eq("3")
    expect(page.at_css("#pages + div").text).to include("CSS grid")
    expect(page.at_css("#countries + div").text).to include("🇮🇳 IN")
    expect(page.css("dl [role=tooltip]").map { |tip| tip.text.strip.split(":").first }).to eq(
      ["The number of distinct users who visited your website in the last 30 minutes.", "Views by page title", "Active users by country", "Active users by device category"]
    )
  end

  it "says why when Analytics can't be read" do
    allow(Google::Analytics::RealtimeService).to receive(:call) {
      snapshot.new(0, {}, {}, {}, ["No Analytics property configured (credentials google.analytics_property_id)"])
    }

    get google_analytics_realtime_path

    expect(Nokogiri::HTML5(response.body).at_css("[role=alert]").text).to include("No Analytics property configured")
  end
end
