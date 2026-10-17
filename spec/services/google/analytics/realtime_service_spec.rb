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
      dimension = JSON.parse(env.body)["dimensions"].first&.fetch("name")
      requests << dimension
      [200, {}, {rows: {
        nil => [{metricValues: [{value: "4"}]}],
        "unifiedScreenName" => rows("About" => 1, "Hello world" => 3),
        "countryId" => rows("IN" => 4),
        "deviceCategory" => rows("mobile" => 3, "desktop" => 1)
      }.fetch(dimension)}.to_json]
    end
  end

  def realtime
    described_class.call(property: 123456789, client: google_client, cache: cache)
  end

  it "breaks down who is active now, most active first, with the total asked for on its own" do
    stub_realtime

    snapshot = realtime
    expect(snapshot.to_h).to eq(
      active_users: 4, pages: {"Hello world" => 3, "About" => 1}, countries: {"IN" => 4}, devices: {"mobile" => 3, "desktop" => 1}, errors: []
    )
    expect(snapshot.pages.keys).to eq(["Hello world", "About"])
  end

  it "reuses a snapshot for a minute" do
    stub_realtime

    2.times { realtime }
    expect(requests.size).to eq(4)
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
