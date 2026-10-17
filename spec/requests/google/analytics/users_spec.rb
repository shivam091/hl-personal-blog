# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics users", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  def table_rows
    Nokogiri::HTML5(response.body).css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.drop(1) }
  end

  it "charts each week's views from new and returning readers" do
    Google::Analytics::VisitorTypeStat.create!(date: yesterday, page_path: "/post/a", visitor_type: "returning", views: 3)
    Google::Analytics::VisitorTypeStat.create!(date: yesterday, page_path: "/post/b", visitor_type: "new", views: 5)

    get google_analytics_users_path

    card = Nokogiri::HTML5(response.body).at_css("#new-and-returning").parent
    expect(card.css("ul li").map(&:text)).to eq(%w[New Returning])
    expect(JSON.parse(card.css("g[data-tip]").last["data-tip"])["rows"].map { |row| row["value"] }).to eq(%w[5 3])
  end

  it "shows the countries breakdown at the bare path" do
    get google_analytics_users_path

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breakdown] a[aria-current=page]").text).to eq("Countries")
  end

  it "charts a breakdown whose rows have no views without failing" do
    Google::Analytics::CountryStat.create!(date: yesterday, page_path: "/post/a", country: "IN", active_users: 1)

    get google_analytics_users_breakdown_path("countries")

    expect(response).to have_http_status(:ok)
  end

  it "shows engagement time in minutes past a minute" do
    Google::Analytics::CountryStat.create!(date: yesterday, page_path: "/post/a", country: "IN", active_users: 1, engagement_seconds: 125.0)

    get google_analytics_users_breakdown_path("countries")

    expect(table_rows.first).to include("🇮🇳 IN", "2m 05s")
  end

  it "totals regions within their country, searchable by region" do
    Google::Analytics::LocationStat.create!(date: yesterday, page_path: "/post/a", country: "IN", region: "Maharashtra", city: "Pune", views: 4)
    Google::Analytics::LocationStat.create!(date: yesterday, page_path: "/post/b", country: "IN", region: "Maharashtra", city: "Mumbai", views: 3)
    Google::Analytics::LocationStat.create!(date: yesterday, page_path: "/post/a", country: "IN", region: "Karnataka", city: "Bengaluru", views: 1)

    get google_analytics_users_breakdown_path("regions", region: "maha")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "🇮🇳 IN", "Maharashtra", "7 (100%)"]])
  end

  it "lists age brackets youngest first, saying why they fall short of the site's traffic" do
    Google::Analytics::AgeStat.create!(date: yesterday, page_path: "/post/a", age_bracket: "35-44", views: 5)
    Google::Analytics::AgeStat.create!(date: yesterday, page_path: "/post/b", age_bracket: "25-34", views: 2)
    Google::Analytics::AgeStat.create!(date: yesterday, page_path: "/post/a", age_bracket: "25-34", views: 1)

    get google_analytics_users_breakdown_path("age")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "25-34", "3 (37.5%)"], ["2", "35-44", "5 (62.5%)"]])
    expect(Nokogiri::HTML5(response.body).text).to include("only once Google signals is on")
  end

  it "totals each gender across pages" do
    Google::Analytics::GenderStat.create!(date: yesterday, page_path: "/post/a", gender: "male", views: 4)
    Google::Analytics::GenderStat.create!(date: yesterday, page_path: "/post/b", gender: "female", views: 6)

    get google_analytics_users_breakdown_path("gender")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "female", "6 (60%)"], ["2", "male", "4 (40%)"]])
  end

  it "totals each language across pages, searchable by language" do
    Google::Analytics::LanguageStat.create!(date: yesterday, page_path: "/post/a", language: "English", views: 6)
    Google::Analytics::LanguageStat.create!(date: yesterday, page_path: "/post/b", language: "English", views: 2)
    Google::Analytics::LanguageStat.create!(date: yesterday, page_path: "/post/a", language: "Hindi", views: 1)

    get google_analytics_users_breakdown_path("languages", language: "eng")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "English", "8 (100%)"]])
  end

  it "totals each screen resolution across pages, the commonest first" do
    Google::Analytics::ScreenResolutionStat.create!(date: yesterday, page_path: "/post/a", screen_resolution: "1920x1080", views: 2)
    Google::Analytics::ScreenResolutionStat.create!(date: yesterday, page_path: "/post/a", screen_resolution: "390x844", views: 3)
    Google::Analytics::ScreenResolutionStat.create!(date: yesterday, page_path: "/post/b", screen_resolution: "390x844", views: 1)

    get google_analytics_users_breakdown_path("screen-resolutions")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "390x844", "4 (66.67%)"], ["2", "1920x1080", "2 (33.33%)"]])
  end

  it "keeps cities of the same name in different countries apart, searchable by city" do
    Google::Analytics::LocationStat.create!(date: yesterday, page_path: "/post/a", country: "US", region: "Texas", city: "Paris", views: 2)
    Google::Analytics::LocationStat.create!(date: yesterday, page_path: "/post/a", country: "FR", region: "Île-de-France", city: "Paris", views: 5)
    Google::Analytics::LocationStat.create!(date: yesterday, page_path: "/post/a", country: "IN", region: "Maharashtra", city: "Pune", views: 9)

    get google_analytics_users_breakdown_path("cities", city: "paris")

    expect(table_rows.map { |row| row.first(5) }).to eq([["1", "🇫🇷 FR", "Île-de-France", "Paris", "5 (71.43%)"], ["2", "🇺🇸 US", "Texas", "Paris", "2 (28.57%)"]])
  end

  it "lists hours and weekdays in time order, by name" do
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, page_path: "/post/a", day_of_week: "1", hour: "21", views: 9)
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, page_path: "/post/a", day_of_week: "0", hour: "09", views: 2)

    get google_analytics_users_breakdown_path("time-of-day")
    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "09:00", "2 (18.18%)"], ["2", "21:00", "9 (81.82%)"]])

    get google_analytics_users_breakdown_path("day-of-week")
    expect(table_rows.map { |row| row[1] }).to eq(%w[Sunday Monday])
    expect(Nokogiri::HTML5(response.body).css("section[aria-labelledby=chart-ranking] li span[title]").map(&:text)).to eq(%w[Monday Sunday])
  end

  it "queues an Analytics sync from its own page" do
    expect {
      post google_analytics_users_sync_path("devices"), params: {google_sync_range: {from: "2026-10-06", to: "2026-10-12"}}
    }.to change(SyncRequest, :count).by(1)
    expect(SyncRequest.last).to have_attributes(kind: "analytics", trigger: "admin")
    expect(response).to redirect_to(google_analytics_users_breakdown_path("devices"))
  end
end
