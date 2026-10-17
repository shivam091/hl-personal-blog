# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics stickiness", type: :request do
  let(:service) { Google::Analytics::StickinessService }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "shows the period's readers and how many come back" do
    days = [
      service::Day.new(date: Date.new(2026, 10, 1), daily: 8, weekly: 50, monthly: 180, dau_per_mau: 0.04, dau_per_wau: 0.16, wau_per_mau: 0.28),
      service::Day.new(date: Date.new(2026, 10, 2), daily: 12, weekly: 60, monthly: 200, dau_per_mau: 0.06, dau_per_wau: 0.2, wau_per_mau: 0.3)
    ]
    allow(service).to receive(:call) { service::Result.new(days: days, errors: []) }

    get google_analytics_stickiness_path(from: "2026-10-01", to: "2026-10-02")

    expect(response).to have_http_status(:ok)
    stats = page.css("dl dd").map { |dd| dd.text.strip }
    expect(stats).to eq(["10", "60", "200", "5.0%"])
    expect(page.at_css("#stickiness")).to be_present
  end

  it "says why when Analytics can't be read" do
    allow(service).to receive(:call) { service::Result.new(days: [], errors: ["Analytics stickiness: quota exhausted"]) }

    get google_analytics_stickiness_path

    expect(page.at_css("[role=alert]").text).to include("quota exhausted")
  end
end
