# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics quota", type: :request do
  def page
    Nokogiri::HTML5(response.body)
  end

  it "shows what's left of each limit, warning when one runs low" do
    Google::Analytics::Quota.record("core", {
      "propertyQuota" => {
        "tokensPerDay" => {"consumed" => 40, "remaining" => 12_000},
        "tokensPerHour" => {"consumed" => 40, "remaining" => 39_000}
      }
    })

    get google_analytics_quota_path

    expect(response).to have_http_status(:ok)

    rows = page.css("#quota-core ~ div tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }

    expect(rows.first(2)).to eq([
      ["Tokens per day", "40", "12,000 of 200,000"],
      ["Tokens per hour", "40", "39,000 of 40,000"]
    ])
    expect(page.at_css("[role=alert]").text.squish).to include("Under 10% left of a limit for Reports")
    expect(page.at_css("#quota-realtime ~ p").text).to include("No realtime requested since quota tracking began.")
  end
end
