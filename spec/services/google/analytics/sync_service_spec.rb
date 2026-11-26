# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::SyncService do
  let(:url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport" }
  let(:today) { Date.new(2026, 10, 11) }
  let(:requests) { [] }

  def row(dimensions, traffic)
    {dimensionValues: dimensions.map { |value| {value: value} }, metricValues: traffic.map { |value| {value: value.to_s} }}
  end

  def stub_reports(reports)
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      requests << body
      # Custom metrics too, so a report asked by page alone isn't answered
      # with the page traffic's rows.
      custom = body["metrics"].map { |metric| metric["name"] }.grep(/\AcustomEvent:/)
      rows = reports.fetch(body["dimensions"].drop(1).map { |dimension| dimension["name"] } + custom, [])
      [200, {}, {rows: rows, rowCount: rows.size}.to_json]
    end
  end

  def sync(**options)
    described_class.call(property: 123456789, client: google_client, today: today, **options)
  end

  it "stores page traffic per day for the requested days" do
    stub_reports(%w[pagePath] => [row(%w[20261010 /post], [12, 9, 4, 10, 7, 345.5, 40, 1])])

    expect(sync(days: 2).summary).to eq("1 created, 0 updated, 0 unchanged, 0 failed")
    expect(requests.first["dateRanges"]).to eq([{"startDate" => "2026-10-10", "endDate" => "2026-10-11"}])
    expect(requests.first["metrics"].map { |metric| metric["name"] }).to eq(described_class::TRAFFIC_METRICS.values)
    expect(Google::Analytics::Stat.all.sole).to have_attributes(
      date: Date.new(2026, 10, 10), page_path: "/post", views: 12, active_users: 9, new_users: 4, sessions: 10,
      engaged_sessions: 7, engagement_seconds: 345.5, event_count: 40, key_events: 1, engagement_rate: 0.7
    )
    expect(Google::Analytics::Stat.all.sole.bounce_rate).to be_within(1e-9).of(0.3)
  end

  it "stores each breakdown in its own model, keyed by page, if it's read by page, and the breakdown's own fields" do
    traffic = [1, 1, 1, 1, 1, 10, 3, 0]
    stub_reports(
      %w[pagePath unifiedScreenClass] => [row(["20261010", "/post", "Post | Harshal V. LADHE"], traffic)],
      %w[pagePath sessionDefaultChannelGroup sessionSource sessionMedium] => [row(%w[20261010 /post Organic\ Search google organic], traffic)],
      %w[pagePath pageReferrer] => [row(%w[20261010 /post https://news.ycombinator.com/], traffic), row(["20261010", "/post", ""], traffic)],
      %w[pagePath countryId] => [row(%w[20261010 /post in], traffic), row(%w[20261010 /post (not\ set)], traffic)],
      %w[countryId region city] => [row(%w[20261010 IN Maharashtra Pune], traffic), row(["20261010", "IN", "", "(not set)"], traffic)],
      %w[pagePath deviceCategory] => [row(%w[20261010 /post mobile], traffic)],
      %w[browser operatingSystem] => [row(%w[20261010 Chrome Android], traffic)],
      %w[language] => [row(%w[20261010 English], traffic)],
      %w[screenResolution] => [row(%w[20261010 390x844], traffic)],
      %w[userAgeBracket] => [row(%w[20261010 25-34], traffic)],
      %w[userGender] => [row(%w[20261010 female], traffic)],
      %w[pagePath newVsReturning] => [row(%w[20261010 /post returning], traffic)],
      %w[landingPage] => [row(%w[20261010 /], traffic)]
    )

    expect(sync.summary).to eq("16 created, 0 updated, 0 unchanged, 0 failed")
    expect(Google::Analytics::PageTitleStat.all.sole).to have_attributes(page_path: "/post", page_title: "Post | Harshal V. LADHE")
    expect(Google::Analytics::SourceStat.all.sole).to have_attributes(page_path: "/post", channel_group: "Organic Search", source: "google", medium: "organic")
    expect(Google::Analytics::ReferrerStat.pluck(:referrer)).to contain_exactly("https://news.ycombinator.com/", "(not set)")
    expect(Google::Analytics::CountryStat.pluck(:country)).to contain_exactly("IN", "ZZ")
    expect(Google::Analytics::LocationStat.pluck(:country, :region, :city)).to contain_exactly(%w[IN Maharashtra Pune], ["IN", "(not set)", "(not set)"])
    expect(Google::Analytics::DeviceStat.all.sole.device).to eq("mobile")
    expect(Google::Analytics::TechnologyStat.all.sole).to have_attributes(page_path: nil, browser: "Chrome", operating_system: "Android")
    expect(Google::Analytics::LanguageStat.all.sole.language).to eq("English")
    expect(Google::Analytics::ScreenResolutionStat.all.sole.screen_resolution).to eq("390x844")
    expect(Google::Analytics::AgeStat.all.sole.age_bracket).to eq("25-34")
    expect(Google::Analytics::GenderStat.all.sole.gender).to eq("female")
    expect(Google::Analytics::VisitorTypeStat.all.sole.visitor_type).to eq("returning")
    expect(Google::Analytics::LandingPageStat.all.sole).to have_attributes(page_path: "/", sessions: 1, engagement_seconds: 10.0)
  end

  it "counts events with their own metrics" do
    stub_reports(%w[pagePath eventName] => [row(%w[20261010 /post scroll], [30, 12, 0, 15])])

    sync
    expect(requests.find { |body| body["dimensions"].last == {"name" => "eventName"} }["metrics"].map { |metric| metric["name"] }).to eq(%w[eventCount activeUsers keyEvents totalUsers])
    expect(Google::Analytics::EventStat.all.sole).to have_attributes(page_path: "/post", event_name: "scroll", event_count: 30, active_users: 12, key_events: 0, total_users: 15)
  end

  it "updates revised figures in place" do
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post", views: 5)
    stub_reports(%w[pagePath] => [row(%w[20261010 /post], [12, 9, 0, 10, 0, 0, 0, 0])])

    expect(sync.summary).to eq("0 created, 1 updated, 0 unchanged, 0 failed")
    expect(Google::Analytics::Stat.all.sole.views).to eq(12)
  end

  it "only asks for traffic on the blog's own hostname" do
    stub_reports({})

    sync
    expect(requests.map { |body| body.dig("dimensionFilter", "andGroup", "expressions", 0) }.uniq).to eq(
      [{"filter" => {"fieldName" => "hostName", "stringFilter" => {"matchType" => "EXACT", "value" => "harshal-ladhe.vercel.app"}}}]
    )
  end

  it "stores first-user sources, reading times and outbound links, asking only for click events' links" do
    traffic = [1, 1, 1, 1, 1, 10, 3, 0]
    stub_reports(
      %w[pagePath firstUserDefaultChannelGroup firstUserSource firstUserMedium] => [row(%w[20261010 /post Referral reddit.com referral], traffic)],
      %w[dayOfWeek hour] => [row(%w[20261010 6 09], traffic)],
      %w[pagePath linkUrl] => [row(%w[20261010 /post https://github.com/x], [4, 2, 0, 3])]
    )

    sync
    expect(Google::Analytics::UserAcquisitionStat.all.sole).to have_attributes(first_channel_group: "Referral", first_source: "reddit.com",
      first_medium: "referral")
    expect(Google::Analytics::TimeOfDayStat.all.sole).to have_attributes(page_path: nil, day_of_week: "6", hour: "09")
    expect(Google::Analytics::OutboundLinkStat.all.sole).to have_attributes(link_url: "https://github.com/x", event_count: 4, total_users: 3)
    links = requests.find { |body| body["dimensions"].last == {"name" => "linkUrl"} }
    expect(links.dig("dimensionFilter", "andGroup", "expressions", 1, "filter"))
      .to eq({"fieldName" => "eventName", "stringFilter" => {"matchType" => "EXACT", "value" => "click", "caseSensitive" => false}})
  end

  it "groups tagged outbound clicks by their ga-* class, summing a link across its other classes" do
    stub_reports(%w[pagePath linkUrl linkClasses] => [
      row(["20261010", "/post", "https://react.dev/", "ga-article-link x1a2"], [2]),
      row(["20261010", "/post", "https://react.dev/", "ga-article-link b3c4"], [1]),
      row(["20261010", "/", "https://github.com/x", "f5 ga-social"], [4]),
      row(["20261010", "/post", "https://example.com/", "not-ga-social"], [7])
    ])

    sync
    expect(Google::Analytics::LinkGroupStat.pluck(:page_path, :link_url, :link_group, :event_count)).to contain_exactly(
      ["/post", "https://react.dev/", "article-link", 3], ["/", "https://github.com/x", "social", 4]
    )
    tagged = requests.find { |body| body["dimensions"].last == {"name" => "linkClasses"} }
    expect(tagged["metrics"]).to eq([{"name" => "eventCount"}])
    expect(tagged.dig("dimensionFilter", "andGroup", "expressions", 2, "filter"))
      .to eq({"fieldName" => "linkClasses", "stringFilter" => {"matchType" => "CONTAINS", "value" => "ga-", "caseSensitive" => false}})
  end

  it "stores labelled events by their label, leaving out events with none" do
    stub_reports(%w[pagePath eventName customEvent:event_label] => [row(%w[20261010 /post share x], [3, 2, 0, 2])])

    sync
    expect(Google::Analytics::EventLabelStat.all.sole).to have_attributes(page_path: "/post", event_name: "share", event_label: "x", event_count: 3)
    labels = requests.find { |body| body["dimensions"].last == {"name" => "customEvent:event_label"} }
    expect(labels.dig("dimensionFilter", "andGroup", "expressions").drop(1)).to eq([
      {"notExpression" => {"filter" => {"fieldName" => "customEvent:event_label", "stringFilter" => {"matchType" => "EXACT", "value" => "(not set)", "caseSensitive" => false}}}},
      {"notExpression" => {"filter" => {"fieldName" => "customEvent:event_label", "stringFilter" => {"matchType" => "EXACT", "value" => "", "caseSensitive" => false}}}}
    ])
  end

  it "stores readers' Web Vitals by rating, scaling CLS back from the thousandfold the blog sends" do
    stub_reports(%w[pagePath eventName customEvent:metric_rating] => [
      row(%w[20261010 /post LCP good], [4, 7200]), row(%w[20261010 /post CLS poor], [2, 600])
    ])

    sync
    vitals = requests.find { |body| body["dimensions"].last == {"name" => "customEvent:metric_rating"} }
    expect(vitals["metrics"].map { |metric| metric["name"] }).to eq(%w[eventCount eventValue])
    expect(vitals.dig("dimensionFilter", "andGroup", "expressions", 1, "filter", "stringFilter", "value")).to eq("LCP|INP|CLS|FCP|TTFB")
    expect(Google::Analytics::WebVitalStat.order(metric: :asc).pluck(:metric, :rating, :event_count, :value_sum)).to eq([
      ["CLS", "poor", 2, 0.6], ["LCP", "good", 4, 7200.0]
    ])
  end

  it "stores each page's content group, category and tags from its page views" do
    stub_reports(%w[pagePath contentGroup customEvent:content_category customEvent:content_tags] => [
      row(%w[20261010 /post tutorial css css,grid], [12])
    ])

    sync
    expect(Google::Analytics::ContentGroupStat.all.sole).to have_attributes(page_path: "/post", content_group: "tutorial",
      content_category: "css", content_tags: "css,grid", views: 12)
  end

  it "stores finished reads with their summed reading time" do
    stub_reports(%w[pagePath customEvent:read_seconds] => [row(%w[20261010 /post], [3, 540])])

    sync
    reads = requests.find { |body| body["metrics"].last == {"name" => "customEvent:read_seconds"} }
    expect(reads.dig("dimensionFilter", "andGroup", "expressions", 1, "filter", "stringFilter", "value")).to eq("article_read")
    expect(Google::Analytics::ArticleReadStat.all.sole).to have_attributes(page_path: "/post", reads: 3, read_seconds: 540)
  end

  it "stores session campaigns with the link they came from" do
    stub_reports(%w[pagePath sessionCampaignName sessionSource sessionMedium sessionManualAdContent] =>
      [row(%w[20261010 /post new_entry newsletter email button], [1, 1, 1, 1, 1, 10, 3, 0])])

    sync
    expect(Google::Analytics::CampaignStat.all.sole).to have_attributes(campaign: "new_entry", source: "newsletter", medium: "email", content: "button")
  end

  it "stores site search terms, found and not, with no page" do
    stub_reports(%w[searchTerm eventName] => [
      row(%w[20261010 grid view_search_results], [5, 3, 0, 4]),
      row(%w[20261010 subgrid search_no_results], [2, 1, 0, 1])
    ])

    sync
    stats = Google::Analytics::SearchTermStat.order(search_term: :asc)
    expect(stats.pluck(:search_term, :event_name, :event_count)).to eq([
      ["grid", "view_search_results", 5],
      ["subgrid", "search_no_results", 2]
    ])

    searches = requests.find do |body|
      names = body["dimensions"].pluck("name")
      names.second == "searchTerm" && names.last == "eventName"
    end
    filter = searches.dig("dimensionFilter", "andGroup", "expressions", 1, "filter", "stringFilter")
    expect(filter).to eq(
      "matchType" => "FULL_REGEXP",
      "value" => "view_search_results|search_no_results",
      "caseSensitive" => false
    )
  end

  it "stores each first-user source's total users, and its returning users from GA's returning sessions alone" do
    dimensions = %w[20261010 /post Referral reddit.com referral]
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      requests << body
      rows =
        if body["dimensions"].last != {"name" => "firstUserMedium"} then []
        elsif body["metrics"] == [{"name" => "activeUsers"}] then [row(dimensions, [3])]
        else [row(dimensions, [9, 5, 2, 6, 4, 120, 20, 1, 7]), row(%w[20261010 /post Direct (direct) (none)], [1, 1, 1, 1, 1, 10, 2, 0, 1])]
        end
      [200, {}, {rows: rows, rowCount: rows.size}.to_json]
    end

    sync
    stats = Google::Analytics::UserAcquisitionStat.order(first_channel_group: :desc).to_a
    expect(stats.map { |stat| [stat.first_channel_group, stat.new_users, stat.total_users, stat.returning_users] })
      .to eq([["Referral", 2, 7, 3], ["Direct", 1, 1, 0]])
    returning = requests.find { |body| body["metrics"] == [{"name" => "activeUsers"}] }
    expect(returning.dig("dimensionFilter", "andGroup", "expressions", 1, "filter"))
      .to eq({"fieldName" => "newVsReturning", "stringFilter" => {"matchType" => "EXACT", "value" => "returning", "caseSensitive" => false}})
  end

  it "stores first-user campaigns and each landing page's sources" do
    traffic = [1, 1, 1, 1, 1, 10, 3, 0]
    stub_reports(
      %w[pagePath firstUserCampaignName firstUserSource firstUserMedium] => [row(%w[20261010 /post new_entry newsletter email], traffic)],
      %w[landingPage sessionDefaultChannelGroup sessionSource sessionMedium] => [row(%w[20261010 / Organic\ Search google organic], traffic)]
    )

    sync
    expect(Google::Analytics::FirstCampaignStat.all.sole).to have_attributes(page_path: "/post", first_campaign: "new_entry",
      first_source: "newsletter", first_medium: "email", new_users: 1)
    expect(Google::Analytics::LandingSourceStat.all.sole).to have_attributes(page_path: "/", channel_group: "Organic Search",
      source: "google", medium: "organic", sessions: 1)
  end

  it "stores the whole site's own daily figures with its rolling actives, asked apart since GA takes ten metrics at most" do
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      requests << body
      rows =
        if body["dimensions"] != [{"name" => "date"}] then []
        elsif body["metrics"].first == {"name" => "active1DayUsers"} then [row(%w[20261010], [9, 30, 80])]
        else [row(%w[20261010], [40, 9, 3, 12, 8, 900.5, 120, 1])]
        end
      [200, {}, {rows: rows, rowCount: rows.size}.to_json]
    end

    sync
    expect(requests.select { |body| body["dimensions"] == [{"name" => "date"}] }.map { |body| body["metrics"].size }).to all(be <= 10)
    expect(Google::Analytics::SiteDayStat.all.sole).to have_attributes(page_path: nil, views: 40, active_users: 9, sessions: 12,
      active_1_day_users: 9, active_7_day_users: 30, active_28_day_users: 80)
  end

  it "stores events by the method they carry, leaving out events with none" do
    stub_reports(%w[pagePath eventName customEvent:method] => [row(%w[20261010 /post cover_image_open new_tab], [2, 2, 0, 2])])

    sync
    expect(Google::Analytics::EventMethodStat.all.sole).to have_attributes(page_path: "/post", event_name: "cover_image_open",
      event_method: "new_tab", event_count: 2)
    methods = requests.find { |body| body["dimensions"].last == {"name" => "customEvent:method"} }
    expect(methods.dig("dimensionFilter", "andGroup", "expressions", 1, "notExpression", "filter", "fieldName")).to eq("customEvent:method")
  end

  it "stores the finished weeks of half a year of weekly cohorts, whatever days were asked for" do
    stub_reports(%w[cohortNthWeek] => [
      row(%w[2026-10-04 0000], [5, 5]), row(%w[2026-10-04 0001], [1, 5]), row(%w[2026-09-27 0001], [2, 8])
    ])

    sync(days: 2)
    cohorts = requests.find { |body| body["cohortSpec"] }
    expect(cohorts.dig("cohortSpec", "cohorts").size).to eq(26)
    expect(Google::Analytics::CohortWeekStat.order(date: :asc).pluck(:date, :week, :active_users, :total_users)).to eq([
      [Date.new(2026, 9, 27), 1, 2, 8], [Date.new(2026, 10, 4), 0, 5, 5]
    ])
  end

  it "asks GA to leave out rows matching an excluding filter" do
    expect(described_class.dimension_filter([["pageReferrer", "CONTAINS", "//example.com", true]]).dig(:andGroup, :expressions, 1))
      .to eq({notExpression: {filter: {fieldName: "pageReferrer", stringFilter: {matchType: "CONTAINS", value: "//example.com", caseSensitive: false}}}})
  end

  it "pages through large reports" do
    stub_const("#{described_class}::ROW_LIMIT", 1)
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      next [200, {}, {rowCount: 0}.to_json] unless body["dimensions"] == [{"name" => "date"}, {"name" => "pagePath"}] &&
        body["metrics"].first == {"name" => "screenPageViews"}

      requests << body["offset"]
      [200, {}, {rows: [row(["20261010", "/p#{body["offset"]}"], [1, 1, 1, 1, 1, 0, 0, 0])], rowCount: 2}.to_json]
    end

    expect(sync.created).to eq(2)
    expect(requests).to eq([0, 1])
  end

  it "handles reports with no rows" do
    google_stubs.post(url) { [200, {}, {rowCount: 0}.to_json] }

    expect(sync.summary).to eq("0 created, 0 updated, 0 unchanged, 0 failed")
  end

  it "reports an API error once instead of raising, still trying the other reports" do
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      next [403, {}, {error: {message: "User does not have sufficient permissions for this property."}}.to_json] unless body["dimensions"].size == 2 && body["dimensions"].last["name"] == "pagePath"

      [200, {}, {rows: [row(%w[20261010 /post], [1, 1, 1, 1, 1, 0, 0, 0])], rowCount: 1}.to_json]
    end

    result = sync
    expect(result.errors).to eq(["Analytics: User does not have sufficient permissions for this property."])
    expect(Google::Analytics::Stat.count).to eq(1)
  end

  it "reports missing configuration" do
    expect(described_class.call(property: nil, client: google_client).errors.first).to include("google.analytics_property_id")
  end
end
