# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::RealtimeService do
  let(:url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runRealtimeReport" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:requests) { [] }

  def rows(counts)
    counts.map { |name, users| {dimensionValues: [{value: name}], metricValues: [{value: users.to_s}]} }
  end

  def stub_realtime
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      dimension = body["dimensions"].first&.fetch("name")
      requests << [dimension, body["metrics"].first["name"]]
      [200, {}, {rows: {
        nil => [{metricValues: [{value: "4"}]}],
        "eventName/keyEvents" => rows("sign_up" => 1, "page_view" => 0),
        "city" => rows("Pune" => 3, "Mumbai" => 1),
        "platform" => rows("web" => 4),
        "minutesAgo" => rows("00" => 1, "02" => 3),
        "unifiedScreenName" => rows("About" => 1, "Hello world" => 5),
        "eventName" => rows("page_view" => 6, "click" => 2),
        "countryId" => rows("IN" => 4),
        "deviceCategory" => rows("mobile" => 3, "desktop" => 1)
      }.fetch(dimension == "eventName" && body["metrics"].first["name"] == "keyEvents" ? "eventName/keyEvents" : dimension)}.to_json]
    end
  end

  def realtime
    described_class.call(property: 123456789, client: google_client, cache: cache)
  end

  it "breaks down who is active now, most active first, with the total asked for on its own" do
    stub_realtime
    now = Time.zone.local(2026, 10, 31, 9, 30)
    snapshot = travel_to(now + 20.seconds) { realtime }
    expect(snapshot.to_h).to eq(
      active_users: 4, pages: {"Hello world" => 5, "About" => 1}, events: {"page_view" => 6, "click" => 2},
      key_events: {"sign_up" => 1}, countries: {"IN" => 4}, cities: {"Pune" => 3, "Mumbai" => 1},
      devices: {"mobile" => 3, "desktop" => 1}, platforms: {"web" => 4},
      per_minute: 29.downto(0).to_h { |ago| [now - ago.minutes, {2 => 3, 0 => 1}.fetch(ago, 0)] }, errors: []
    )
    expect(snapshot.pages.keys).to eq(["Hello world", "About"])
  end

  it "counts pages by views and events by count, as GA's Realtime cards do" do
    stub_realtime

    realtime
    expect(requests).to include(["unifiedScreenName", "screenPageViews"], ["eventName", "eventCount"], ["eventName", "keyEvents"], ["countryId", "activeUsers"])
  end

  it "reuses a snapshot for a minute" do
    stub_realtime

    2.times { realtime }
    expect(requests.size).to eq(9)
  end

  it "reports an API error instead of raising" do
    google_stubs.post(url) { [403, {}, {error: {message: "User does not have sufficient permissions for this property."}}.to_json] }

    expect(realtime.errors).to eq(["Analytics realtime: User does not have sufficient permissions for this property."])
  end

  it "counts one event's triggers now, by country, asking only for that event" do
    bodies = []
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      bodies << body
      [200, {}, {rows: body["dimensions"].empty? ? [{metricValues: [{value: "5"}]}] : rows("US" => 1, "IN" => 4)}.to_json]
    end

    snapshot = described_class.event("click", property: 123456789, client: google_client, cache: cache)

    expect(snapshot.to_h).to eq(event_count: 5, countries: {"IN" => 4, "US" => 1}, errors: [])
    expect(bodies.map { |body| body["metrics"] }.uniq).to eq([[{"name" => "eventCount"}]])
    expect(bodies.map { |body| body["dimensionFilter"] }.uniq)
      .to eq([{"filter" => {"fieldName" => "eventName", "stringFilter" => {"matchType" => "EXACT", "value" => "click"}}}])
  end

  it "reports missing configuration" do
    expect(described_class.call(property: nil, client: google_client).errors.first).to include("google.analytics_property_id")
  end
end
