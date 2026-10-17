# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics cohorts", type: :request do
  let(:service) { Google::Analytics::CohortService }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "shows each weekly cohort's share coming back" do
    cohorts = [
      service::Cohort.new(
        start: Date.new(2026, 9, 27),
        users: 40,
        active: {0 => 40, 1 => 6, 2 => 2}
      )
    ]
    allow(service).to receive(:call) { service::Result.new(cohorts: cohorts, weeks: 3, errors: []) }

    get google_analytics_cohorts_path

    expect(response).to have_http_status(:ok)
    row = page.at_css("#cohorts ~ div tbody tr")
    expect(row.at_css("th").text.strip).to eq("Week of 27 Sep")
    expect(row.css("td").map { |td| td.text.strip }).to eq(["40", "15%", "5%"])
  end

  it "says why when Analytics can't be read" do
    allow(service).to receive(:call) {
      service::Result.new(cohorts: [], weeks: 12, errors: ["Analytics cohorts: quota exhausted"])
    }

    get google_analytics_cohorts_path

    expect(page.at_css("[role=alert]").text).to include("quota exhausted")
  end
end
