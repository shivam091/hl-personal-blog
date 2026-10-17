# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics retention", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  it "shows new and returning readers at the bare path" do
    Google::Analytics::VisitorTypeStat.create!(date: yesterday, page_path: "/post/a", visitor_type: "new", views: 3)
    Google::Analytics::VisitorTypeStat.create!(date: yesterday, page_path: "/post/b", visitor_type: "returning", views: 2)

    get google_analytics_retention_path

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("nav[aria-label=Breakdown] a[aria-current=page]").text).to eq("New vs returning")
    expect(page.at_css("tbody").text).to include("new", "returning")
  end

  it "no longer lists new vs returning under Users" do
    get google_analytics_users_path

    expect(Nokogiri::HTML5(response.body).css("nav[aria-label=Breakdown] a").map(&:text)).not_to include("New vs returning")
  end
end
