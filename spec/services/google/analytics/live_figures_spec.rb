# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::LiveFigures do
  let(:url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport" }
  let(:requests) { [] }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  def row(dimensions, metrics)
    {dimensionValues: dimensions.map { |value| {value: value} }, metricValues: metrics.map { |value| {value: value.to_s} }}
  end

  def stub_reports(by_dimensions, total)
    google_stubs.post(url) do |env|
      body = JSON.parse(env.body)
      requests << body
      rows = body["dimensions"].empty? ? [row([], total)] : by_dimensions
      [200, {}, {rows: rows, rowCount: rows.size}.to_json]
    end
  end

  def figures(**options)
    described_class.new(property: 123456789, client: google_client, cache: cache)
      .call(from: Date.new(2026, 9, 15), to: Date.new(2026, 10, 12), dimensions: {country: "countryId"},
        metrics: {total_users: "totalUsers", active_users: "activeUsers"}, **options)
  end

  it "asks for each row and, apart, for the period's total, keyed as rows are stored" do
    stub_reports([row(%w[in], [80, 79]), row(["(not set)"], [3, 3])], [101, 100])

    result = figures(filters: [["pagePath", "CONTAINS", "/post/"]])

    expect(result.rows).to eq(%w[IN] => {total_users: 80, active_users: 79}, %w[ZZ] => {total_users: 3, active_users: 3})
    expect(result.total).to eq(total_users: 101, active_users: 100)
    expect(requests.map { |body| body["dimensions"] }).to eq([[{"name" => "countryId"}], []])
    expect(requests.first["dateRanges"]).to eq([{"startDate" => "2026-09-15", "endDate" => "2026-10-12"}])
    expect(requests.first["dimensionFilter"]["andGroup"]["expressions"].map { |expression| expression["filter"] }).to eq([
      {"fieldName" => "hostName", "stringFilter" => {"matchType" => "EXACT", "value" => "harshal-ladhe.vercel.app"}},
      {"fieldName" => "pagePath", "stringFilter" => {"matchType" => "CONTAINS", "value" => "/post/", "caseSensitive" => false}}
    ])
  end

  it "keeps figures a while, since a report reloads as it's sorted and paged" do
    stub_reports([row(%w[in], [1, 1])], [1, 1])

    2.times { figures }

    expect(requests.size).to eq(2)
  end

  it "says why when GA can't be asked" do
    google_stubs.post(url) { [403, {}, {error: {message: "User does not have sufficient permissions"}}.to_json] }

    expect { figures }.to raise_error(described_class::Unavailable, /sufficient permissions/)
    expect { described_class.new(property: "", client: google_client, cache: cache).call(from: Date.current, to: Date.current, dimensions: {}, metrics: {}) }
      .to raise_error(described_class::Unavailable, "no Analytics property is configured")
  end
end
