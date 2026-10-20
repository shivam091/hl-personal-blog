# encoding: UTF-8

require "rails_helper"

RSpec.describe "Link safety", type: :request do
  include ActiveJob::TestHelper

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    Google::SafeBrowsing::LinkCheck.create!(url: "https://github.com/x", checked_at: 1.hour.ago)
    Google::SafeBrowsing::LinkCheck.create!(
      url: "http://bad.example/",
      threat_types: ["SOCIAL_ENGINEERING"],
      flagged_at: 1.day.ago,
      checked_at: 1.hour.ago
    )
  end

  it "warns about flagged links and lists them first" do
    get google_safe_browsing_link_checks_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("[role=alert]").text.squish).to include("1 link readers clicked is listed by Google as unsafe.")
    rows = page.css("table tbody tr").map do |row|
      row.css("td").map { |td| td.text.squish }
    end
    expect(rows.map { |cells| cells.values_at(1, 2) }).to eq([
      ["http://bad.example/", "Phishing or deception"],
      ["https://github.com/x", "Safe"]
    ])
  end

  it "filters to flagged links" do
    get google_safe_browsing_link_checks_path(status: "flagged")

    expect(page.css("table tbody tr").size).to eq(1)
  end

  it "queues a check" do
    expect {
      post sync_google_safe_browsing_link_checks_path
    }.to have_enqueued_job(Google::SafeBrowsing::SyncJob)
  end
end
