# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::SyncService do
  let(:site) { "sc-domain:blog.example.com" }
  let(:url) { "https://searchconsole.googleapis.com/webmasters/v3/sites/sc-domain%3Ablog.example.com/searchAnalytics/query" }
  let(:today) { Date.new(2026, 10, 11) }
  let(:requests) { [] }
  let(:site_response) { [200, {}, {siteUrl: site, permissionLevel: "siteFullUser"}.to_json] }

  before { google_stubs.get("https://searchconsole.googleapis.com/webmasters/v3/sites/sc-domain%3Ablog.example.com") { site_response } }

  def stub_reports(reports, incomplete = {})
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      requests << body
      dimensions = body["dimensions"]
      if dimensions.include?("searchAppearance") && dimensions.size > 1
        next [400, {}, {error: {message: "Cannot group by search appearance dimension together with another dimension."}}.to_json]
      end
      if body["type"] == "discover" && dimensions.include?("device")
        next [400, {}, {error: {message: "Requests for Discover cannot be grouped by device"}}.to_json]
      end

      appearance = body.dig("dimensionFilterGroups", 0, "filters", 0, "expression")
      key = if appearance then "searchAppearance:#{appearance}"
      elsif dimensions == ["searchAppearance"] then "searchAppearance:listed"
      else (dimensions - %w[date page]).join("+").presence
      end
      site_wide = !dimensions.include?("page") && dimensions != ["searchAppearance"]
      metadata = ({first_incomplete_date: incomplete[body["type"]]} if incomplete[body["type"]] && dimensions.include?("date"))
      [200, {}, {rows: reports.fetch(site_wide ? [body["type"], :site, key] : [body["type"], key], []), metadata: metadata}.compact.to_json]
    end
  end

  def row(*keys, clicks: 1, impressions: 10, ctr: 0.1, position: 3.0)
    {keys: keys, clicks: clicks, impressions: impressions, ctr: ctr, position: position}
  end

  def sync(**options)
    described_class.call(site: site, client: google_client, today: today, **options)
  end

  it "stores page totals and per-query rows for the requested days, with the page's path" do
    stub_reports(
      ["web", nil] => [row("2026-10-10", "https://blog.example.com/post", clicks: 5, impressions: 100, ctr: 0.05, position: 7.2)],
      ["web", "query"] => [row("2026-10-10", "https://blog.example.com/post", "rails tips", clicks: 3)]
    )

    expect(sync(days: 3).summary).to eq("2 created, 0 updated, 0 unchanged, 0 failed")
    expect(requests.first).to include("startDate" => "2026-10-09", "endDate" => "2026-10-11", "dataState" => "all", "type" => "web")
    expect(Google::SearchConsole::Stat.page_totals.sole).to have_attributes(
      date: Date.new(2026, 10, 10), search_type: "web", page: "https://blog.example.com/post", page_path: "/post",
      query: nil, clicks: 5, impressions: 100, ctr: 0.05, position: 7.2
    )
    expect(Google::SearchConsole::Stat.by_query.sole).to have_attributes(query: "rails tips", clicks: 3, page_path: "/post")
  end

  it "also stores Search Console's site-wide figures, without a page, beside the per-page ones" do
    stub_reports(
      ["web", nil] => [row("2026-10-10", "https://blog.example.com/a", clicks: 2), row("2026-10-10", "https://blog.example.com/b", clicks: 2)],
      ["web", :site, nil] => [row("2026-10-10", clicks: 3, impressions: 40)],
      ["web", :site, "query"] => [row("2026-10-10", "rails tips", clicks: 1)],
      ["web", "searchAppearance:listed"] => [row("VIDEO")],
      ["web", :site, "searchAppearance:VIDEO"] => [row("2026-10-10", clicks: 1)]
    )

    expect(sync.errors).to be_empty
    expect(Google::SearchConsole::Stat.site_totals.sole).to have_attributes(page: nil, page_path: nil, clicks: 3, impressions: 40)
    expect(Google::SearchConsole::Stat.page_totals.sum(:clicks)).to eq(4)
    expect(Google::SearchConsole::Stat.by_query.site_wide.sole).to have_attributes(query: "rails tips", clicks: 1)
    expect(Google::SearchConsole::AppearanceStat.site_wide.sole).to have_attributes(appearance: "VIDEO", clicks: 1)
  end

  it "stores queries by country for the whole site only, coding countries as their own tab does" do
    stub_reports(["web", :site, "query+country"] => [row("2026-10-10", "rails tips", "usa", clicks: 2)])

    expect(sync.errors).to be_empty
    expect(Google::SearchConsole::QueryCountryStat.all.sole).to have_attributes(page: nil, query: "rails tips", country: "US", clicks: 2)
    crossed = requests.select { |body| (body["dimensions"] & %w[query country device]).size > 1 }
    expect(crossed.map { |body| body["dimensions"] }.uniq).to eq([%w[date query country]])
    expect(crossed.map { |body| body["type"] }.uniq).not_to include("discover", "googleNews")
  end

  it "fetches hours for the last ten days, storing each at its UTC start on its Pacific day" do
    stub_reports(
      ["web", :site, "hour"] => [row("2026-10-10T13:00:00-07:00", clicks: 2, impressions: 20)],
      ["web", "hour"] => [row("2026-10-10T13:00:00-07:00", "https://blog.example.com/post", clicks: 2, impressions: 20)]
    )

    expect(sync(days: 30).errors).to be_empty
    hourly = requests.select { |body| body["dimensions"].include?("hour") && body["type"] == "web" }
    expect(hourly.map { |body| body.slice("dataState", "startDate", "endDate") }.uniq)
      .to eq([{"dataState" => "hourly_all", "startDate" => "2026-10-02", "endDate" => "2026-10-11"}])
    expect(hourly.map { |body| body["dimensions"] }).to contain_exactly(%w[hour page], %w[hour])
    expect(Google::SearchConsole::HourStat.site_wide.sole).to have_attributes(hour_at: Time.utc(2026, 10, 10, 20), date: Date.new(2026, 10, 10), clicks: 2)
    expect(Google::SearchConsole::HourStat.per_page.sole).to have_attributes(page_path: "/post", hour_at: Time.utc(2026, 10, 10, 20))
    expect(Google::SearchConsole::Stat.count).to eq(0)
  end

  it "fetches the full ten days of hours even when the range is shorter" do
    stub_reports(["web", :site, "hour"] => [], ["web", "hour"] => [])

    expect(sync(days: 3).errors).to be_empty
    hourly = requests.select { |body| body["dimensions"].include?("hour") && body["type"] == "web" }
    expect(hourly.map { |body| body.slice("startDate", "endDate") }.uniq).to eq([{"startDate" => "2026-10-02", "endDate" => "2026-10-11"}])
  end

  it "skips a run while another is syncing, rather than inserting the same rows twice" do
    stub_reports({})
    SyncLock.collection.insert_one(_id: "google/search_console/performance", expires_at: 10.minutes.from_now)

    expect(sync.errors).to eq(["Search Console: another sync is already running, so this one was skipped"])
    expect(requests).to be_empty
  end

  it "stores each breakdown in its own model, with countries and devices named as Analytics names them" do
    stub_reports(
      ["web", "country"] => [row("2026-10-10", "https://blog.example.com/", "ind"), row("2026-10-10", "https://blog.example.com/", "zzz")],
      ["web", "device"] => [row("2026-10-10", "https://blog.example.com/", "MOBILE")]
    )

    result = sync
    expect(result.errors).to be_empty
    expect(result.created).to eq(3)
    expect(Google::SearchConsole::CountryStat.pluck(:country)).to contain_exactly("IN", "ZZ")
    expect(Google::SearchConsole::DeviceStat.all.sole).to have_attributes(device: "mobile", page_path: "/")
  end

  it "lists search appearances alone, then fetches each one's pages and days through a filter" do
    stub_reports(
      ["web", "searchAppearance:listed"] => [row("VIDEO"), row("FAQ_RICH_RESULT")],
      ["web", "searchAppearance:VIDEO"] => [row("2026-10-10", "https://blog.example.com/a", clicks: 4)],
      ["web", "searchAppearance:FAQ_RICH_RESULT"] => [row("2026-10-09", "https://blog.example.com/b", clicks: 2)]
    )

    result = sync
    expect(result.errors).to be_empty
    expect(Google::SearchConsole::AppearanceStat.order(appearance: :asc).map { |stat| [stat.appearance, stat.date, stat.page_path, stat.clicks] }).to eq([
      ["FAQ_RICH_RESULT", Date.new(2026, 10, 9), "/b", 2],
      ["VIDEO", Date.new(2026, 10, 10), "/a", 4]
    ])
  end

  it "asks for no device split on Discover, which Search Console refuses" do
    stub_reports({})

    expect(sync.errors).to be_empty
    expect(requests.select { |body| body["dimensions"].include?("device") }.map { |body| body["type"] })
      .to match_array((Google::SearchConsole::Performance::SEARCH_TYPES - %w[discover]) * 2)
  end

  it "keeps each search type's figures apart, and asks Discover and Google News for no queries" do
    stub_reports(
      ["web", nil] => [row("2026-10-10", "https://blog.example.com/post", clicks: 5)],
      ["discover", nil] => [row("2026-10-10", "https://blog.example.com/post", clicks: 9)]
    )

    expect(sync.created).to eq(2)
    expect(Google::SearchConsole::Stat.where(search_type: "discover").sole.clicks).to eq(9)
    queried_types = requests.select { |body| body["dimensions"].include?("query") }.map { |body| body["type"] }
    expect(queried_types).to match_array((Google::SearchConsole::Performance::SEARCH_TYPES - %w[discover googleNews]) * 3)
  end

  it "updates revised figures in place, and fills in the search type on rows stored before it existed" do
    Google::SearchConsole::Stat.collection.insert_one(date: Date.new(2026, 10, 9), page: "https://blog.example.com/a", clicks: 1, impressions: 10, ctr: 0.1, position: 3.0)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 10), page: "https://blog.example.com/a", page_path: "/a", clicks: 1, impressions: 10, ctr: 0.1, position: 3.0)
    stub_reports(["web", nil] => [
      row("2026-10-09", "https://blog.example.com/a"),
      row("2026-10-10", "https://blog.example.com/a", clicks: 2, impressions: 12, ctr: 0.1667, position: 2.5)
    ])

    expect(sync.summary).to eq("0 created, 2 updated, 0 unchanged, 0 failed")
    expect(Google::SearchConsole::Stat.count).to eq(2)
    expect(Google::SearchConsole::Stat.find_by(date: Date.new(2026, 10, 10)).clicks).to eq(2)
    expect(Google::SearchConsole::Stat.collection.find(date: Date.new(2026, 10, 9)).first).to include("search_type" => "web", "page_path" => "/a")
  end

  it "pages through large reports" do
    stub_const("#{described_class}::ROW_LIMIT", 1)
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      page_totals = body["type"] == "web" && body["dimensions"] == %w[date page] && !body.key?("dimensionFilterGroups")
      requests << body if page_totals
      rows = !page_totals || body["startRow"] > 1 ? [] : [row("2026-10-10", "https://blog.example.com/p#{body["startRow"]}")]
      [200, {}, {rows: rows}.to_json]
    end

    expect(sync.created).to eq(2)
    expect(requests.map { |body| body["startRow"] }).to eq([0, 1, 2])
  end

  it "reports an API error once instead of raising, still trying the other reports" do
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      next [403, {}, {error: {message: "User does not have sufficient permission for site"}}.to_json] unless body["dimensions"][2] == "device"

      [200, {}, {rows: body["type"] == "web" ? [row("2026-10-10", "https://blog.example.com/", "DESKTOP")] : []}.to_json]
    end

    result = sync
    expect(result.errors).to eq(["Search Console: User does not have sufficient permission for site"])
    expect(Google::SearchConsole::DeviceStat.count).to eq(1)
  end

  context "when the service account can't read the property" do
    let(:site_response) { [200, {}, {siteUrl: site, permissionLevel: "siteUnverifiedUser"}.to_json] }

    it "says so once and asks for no reports" do
      stub_reports({})

      expect(sync.errors).to eq(["Search Console: the service account is siteUnverifiedUser on #{site}, which can read none of its data. Add it under Settings › Users and permissions."])
      expect(requests).to be_empty
    end
  end

  context "when the property can't be opened at all" do
    let(:site_response) { [403, {}, {error: {message: "User does not have sufficient permission for site"}}.to_json] }

    it "names the property and Google's reason, and asks for no reports" do
      stub_reports({})

      expect(sync.errors.sole).to start_with("Search Console: can't open #{site} (User does not have sufficient permission for site).")
      expect(requests).to be_empty
    end
  end

  it "records the earliest day any search type still calls incomplete, so the next run starts there" do
    stub_reports({}, {"web" => "2026-10-10", "discover" => "2026-10-09"})

    expect(sync(days: 7).errors).to be_empty
    expect(Google::SearchConsole::FinalDate.first_incomplete_date).to eq(Date.new(2026, 10, 9))
    expect(described_class.unsettled_days(today)).to eq(3)
  end

  it "falls back to the last few days when Google marks none incomplete" do
    stub_reports({})

    sync(days: 7)
    expect(Google::SearchConsole::FinalDate.first_incomplete_date).to eq(Date.new(2026, 10, 9))
  end

  it "leaves the recorded day alone after a run that failed a report, or one that didn't reach it" do
    Google::SearchConsole::FinalDate.record(Date.new(2026, 10, 1))
    google_stubs.post(url) { [403, {}, {error: {message: "No access"}}.to_json] }
    sync(days: 30)
    expect(Google::SearchConsole::FinalDate.first_incomplete_date).to eq(Date.new(2026, 10, 1))

    google_stubs.post(url) { [200, {}, {rows: [], metadata: {first_incomplete_date: "2026-10-10"}}.to_json] }
    sync(days: 3)
    expect(Google::SearchConsole::FinalDate.first_incomplete_date).to eq(Date.new(2026, 10, 1))
  end

  it "syncs the default window until a run has recorded a day" do
    expect(described_class.unsettled_days(today)).to eq(described_class::DEFAULT_DAYS)
  end

  it "reports missing configuration" do
    expect(described_class.call(site: nil, client: google_client).errors.first).to include("google.search_console_site")
    expect(described_class.call(site: site, client: google_client(client_email: nil)).errors.first).to include("google.client_email")
  end
end
