# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::PivotService do
  let(:url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runPivotReport" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }
  let(:bodies) { [] }

  def pivot(property: 123456789, **picks)
    described_class.new(property: property, client: google_client, cache: cache).call(period, **picks)
  end

  before do
    google_stubs.post(url) do |env|
      bodies << JSON.parse(env.body)
      cell = ->(row, column, value) { {dimensionValues: [{value: row}, {value: column}, {value: "example.com"}], metricValues: [{value: value.to_s}]} }
      header = ->(*values) { {pivotDimensionHeaders: values.map { |value| {dimensionValues: [{value: value}]} }} }
      [200, {}, {
        dimensionHeaders: [{name: "sessionDefaultChannelGroup"}, {name: "deviceCategory"}, {name: "hostName"}],
        pivotHeaders: [header.("Organic Search", "Direct"), header.("mobile", "desktop"), header.("example.com")],
        rows: [cell.("Organic Search", "mobile", 30), cell.("Organic Search", "desktop", 12), cell.("Direct", "desktop", 5)],
        aggregates: [cell.("Organic Search", "RESERVED_TOTAL", 40), cell.("Direct", "RESERVED_TOTAL", 5),
          cell.("RESERVED_TOTAL", "mobile", 30), cell.("RESERVED_TOTAL", "desktop", 16), cell.("RESERVED_TOTAL", "RESERVED_TOTAL", 44)]
      }.to_json]
    end
  end

  it "asks GA for readers by channel and device, totalled, by default" do
    result = pivot

    body = bodies.first
    expect(body["dimensions"]).to eq([{"name" => "sessionDefaultChannelGroup"}, {"name" => "deviceCategory"}, {"name" => "hostName"}])
    expect(body["metrics"]).to eq([{"name" => "activeUsers"}])
    expect(body["pivots"].map { |pivot| [pivot["fieldNames"], pivot["limit"], pivot["metricAggregations"]] })
      .to eq([[["sessionDefaultChannelGroup"], 15, ["TOTAL"]], [["deviceCategory"], 8, ["TOTAL"]], [["hostName"], 1, nil]])
    expect([result.rows, result.columns, result.metric]).to eq(%w[channel device readers])
  end

  it "reads the grid in GA's order, with GA's own totals" do
    table = pivot.table

    expect(table.rows).to eq(["Organic Search", "Direct"])
    expect(table.columns).to eq(%w[mobile desktop])
    expect([table["Organic Search", "mobile"], table["Direct", "mobile"]]).to eq([30, nil])
    expect(table.row_totals).to eq("Organic Search" => 40, "Direct" => 5)
    expect(table.column_totals).to eq("mobile" => 30, "desktop" => 16)
    expect(table.total).to eq(44)
  end

  it "reads picks not offered, or columns the same as rows, as the defaults" do
    result = pivot(rows: "device", columns: "device", metric: "planets")

    expect([result.rows, result.columns, result.metric]).to eq(%w[device channel readers])
  end

  it "exports the grid with its totals" do
    csv = CSV.parse(described_class.to_csv(pivot))

    expect(csv.first).to eq(%w[Channel mobile desktop Total])
    expect(csv.second).to eq(["Organic Search", "30", "12", "40"])
    expect(csv.last).to eq(%w[Total 30 16 44])
  end

  it "says why when Analytics isn't configured" do
    expect(pivot(property: "").errors).to eq(["No Analytics property configured (credentials google.analytics_property_id)"])
  end
end
