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
    Google::Analytics::LocationStat.create!(date: yesterday, country: "IN", region: "Maharashtra", city: "Pune", views: 4)
    Google::Analytics::LocationStat.create!(date: yesterday, country: "IN", region: "Maharashtra", city: "Mumbai", views: 3)
    Google::Analytics::LocationStat.create!(date: yesterday, country: "IN", region: "Karnataka", city: "Bengaluru", views: 1)

    get google_analytics_users_breakdown_path("regions", region: "maha")

    expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breakdown] a[aria-current=page]").text.squish).to eq("Countries")
    expect(Nokogiri::HTML5(response.body).at_css("thead select#breakdown-split option[selected]").text).to eq("By region")
    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "🇮🇳 IN", "Maharashtra", "7 (100%)"]])
  end

  it "lists age brackets youngest first, saying why they fall short of the site's traffic" do
    Google::Analytics::AgeStat.create!(date: yesterday, age_bracket: "35-44", views: 5)
    Google::Analytics::AgeStat.create!(date: yesterday, age_bracket: "25-34", views: 3)

    get google_analytics_users_breakdown_path("age")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "25-34", "3 (37.5%)"], ["2", "35-44", "5 (62.5%)"]])
    expect(Nokogiri::HTML5(response.body).text).to include("only once Google signals is on")
  end

  it "lists each gender for the whole site" do
    Google::Analytics::GenderStat.create!(date: yesterday, gender: "male", views: 4)
    Google::Analytics::GenderStat.create!(date: yesterday, gender: "female", views: 6)

    get google_analytics_users_breakdown_path("gender")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "female", "6 (60%)"], ["2", "male", "4 (40%)"]])
  end

  it "lists each language for the whole site, searchable by language" do
    Google::Analytics::LanguageStat.create!(date: yesterday, language: "English", views: 8)
    Google::Analytics::LanguageStat.create!(date: yesterday, language: "Hindi", views: 1)

    get google_analytics_users_breakdown_path("languages", language: "eng")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "English", "8 (100%)"]])
  end

  it "lists each screen resolution for the whole site, the commonest first" do
    Google::Analytics::ScreenResolutionStat.create!(date: yesterday, screen_resolution: "1920x1080", views: 2)
    Google::Analytics::ScreenResolutionStat.create!(date: yesterday, screen_resolution: "390x844", views: 4)

    get google_analytics_users_breakdown_path("screen-resolutions")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "390x844", "4 (66.67%)"], ["2", "1920x1080", "2 (33.33%)"]])
  end

  it "says a breakdown stored for the whole site can't be searched by page" do
    Google::Analytics::LanguageStat.create!(date: yesterday, language: "English", views: 8)

    get google_analytics_users_breakdown_path("languages", path: "/post/a")

    expect(Nokogiri::HTML5(response.body).text).to include("Languages is stored for the whole site only, not by page. Remove the page search.")
    expect(table_rows).to be_empty
  end

  it "keeps cities of the same name in different countries apart, searchable by city" do
    Google::Analytics::LocationStat.create!(date: yesterday, country: "US", region: "Texas", city: "Paris", views: 2)
    Google::Analytics::LocationStat.create!(date: yesterday, country: "FR", region: "Île-de-France", city: "Paris", views: 5)
    Google::Analytics::LocationStat.create!(date: yesterday, country: "IN", region: "Maharashtra", city: "Pune", views: 9)

    get google_analytics_users_breakdown_path("cities", city: "paris")

    expect(table_rows.map { |row| row.first(5) }).to eq([["1", "🇫🇷 FR", "Île-de-France", "Paris", "5 (71.43%)"], ["2", "🇺🇸 US", "Texas", "Paris", "2 (28.57%)"]])
  end

  it "lists hours and weekdays in time order, by name" do
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, day_of_week: "1", hour: "21", views: 9)
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, day_of_week: "0", hour: "09", views: 2)

    get google_analytics_users_breakdown_path("time-of-day")
    expect(table_rows.map { |row| row.first(3) }).to eq([["1", "09:00", "2 (18.18%)"], ["2", "21:00", "9 (81.82%)"]])

    get google_analytics_users_breakdown_path("day-of-week")
    expect(table_rows.map { |row| row[1] }).to eq(%w[Sunday Monday])
    expect(Nokogiri::HTML5(response.body).css("section[aria-labelledby=chart-ranking] li span[title]").map(&:text)).to eq(%w[Monday Sunday])
  end

  it "offers each tab's splits under its column rather than as tabs" do
    # A row in each, since the column, and its menu, only show with rows.
    row = {date: yesterday, page_path: "/post/a", views: 1}
    site = {date: yesterday, views: 1}
    Google::Analytics::CountryStat.create!(**row, country: "IN")
    Google::Analytics::LocationStat.create!(**site, country: "IN", region: "Maharashtra", city: "Pune")
    Google::Analytics::DeviceStat.create!(**row, device: "mobile")
    Google::Analytics::TechnologyStat.create!(**site, browser: "Chrome", operating_system: "Android")
    Google::Analytics::AgeStat.create!(**site, age_bracket: "25-34")
    Google::Analytics::GenderStat.create!(**site, gender: "female")
    Google::Analytics::LanguageStat.create!(**site, language: "English")
    Google::Analytics::ScreenResolutionStat.create!(**site, screen_resolution: "390x844")
    Google::Analytics::TimeOfDayStat.create!(**site, day_of_week: "1", hour: "09")
    {
      "countries" => ["By page", "By region", "By region and city"], "devices" => ["By page"], "day-of-week" => ["By hour"]
    }.each do |tab, splits|
      get google_analytics_users_breakdown_path(tab)

      expect(Nokogiri::HTML5(response.body).css("thead select#breakdown-split option").map(&:text)).to eq(["No split", *splits]), tab
    end
    # Stored for the whole site, so there's nothing to split them by.
    %w[technology age gender languages screen-resolutions time-of-day].each do |tab|
      get google_analytics_users_breakdown_path(tab)

      expect(Nokogiri::HTML5(response.body).at_css("thead select#breakdown-split")).to be_nil, tab
    end
    expect(Nokogiri::HTML5(response.body).css("nav[aria-label=Breakdown] a").map { |tab| tab.text.squish }).to eq(
      ["Countries", "Devices", "Technology", "Age", "Gender", "Languages", "Screen resolution", "Time of day", "Day of week"]
    )
  end

  it "splits a country by page, keeping its country search" do
    Google::Analytics::CountryStat.create!(date: yesterday, page_path: "/post/a", country: "IN", views: 4)
    Google::Analytics::CountryStat.create!(date: yesterday, page_path: "/post/b", country: "IN", views: 1)
    Google::Analytics::CountryStat.create!(date: yesterday, page_path: "/post/a", country: "US", views: 9)

    get google_analytics_users_breakdown_path("country-pages", country: "IN")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "🇮🇳 IN", "/post/a", "4 (80%)"], ["2", "🇮🇳 IN", "/post/b", "1 (20%)"]])
  end

  it "splits each weekday by its hours, in time order" do
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, day_of_week: "1", hour: "21", views: 9)
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, day_of_week: "1", hour: "09", views: 1)
    Google::Analytics::TimeOfDayStat.create!(date: yesterday, day_of_week: "0", hour: "21", views: 2)

    get google_analytics_users_breakdown_path("day-of-week-hours")

    expect(table_rows.map { |row| row.first(3) }).to eq([%w[1 Sunday 21:00], %w[2 Monday 09:00], %w[3 Monday 21:00]])
  end

  it "queues an Analytics sync from its own page" do
    expect {
      post google_analytics_users_sync_path("devices"), params: {google_sync_range: {from: "2026-10-06", to: "2026-10-12"}}
    }.to change(SyncRequest, :count).by(1)
    expect(SyncRequest.last).to have_attributes(kind: "analytics", trigger: "admin")
    expect(response).to redirect_to(google_analytics_users_breakdown_path("devices"))
  end
end
