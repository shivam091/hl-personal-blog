# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::StickinessService do
  let(:url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-03"}, today: Date.new(2026, 10, 12)) }
  let(:bodies) { [] }

  def stickiness(property: 123456789)
    described_class.new(property: property, client: google_client, cache: cache).call(period)
  end

  before do
    google_stubs.post(url) do |env|
      bodies << JSON.parse(env.body)
      [200, {}, {
        dimensionHeaders: [{name: "date"}],
        metricHeaders: %w[active1DayUsers active7DayUsers active28DayUsers dauPerMau dauPerWau wauPerMau].map { |name| {name: name} },
        rows: [["20261003", 12, 60, 200, 0.06, 0.2, 0.3], ["20261001", 8, 50, 180, 0.04, 0.16, 0.28]].map do |date, *values|
          {dimensionValues: [{value: date}], metricValues: values.map { |value| {value: value.to_s} }}
        end
      }.to_json]
    end
  end

  it "reads each day's rolling readers and ratios, leaving a day GA had no row for blank" do
    result = stickiness

    expect(bodies.first["metrics"].map { |metric| metric["name"] }).to include("active28DayUsers", "dauPerMau")
    expect(bodies.first.dig("dimensionFilter", "andGroup", "expressions", 0, "filter", "fieldName")).to eq("hostName")
    expect(result.days.map(&:date)).to eq([Date.new(2026, 10, 1), Date.new(2026, 10, 2), Date.new(2026, 10, 3)])
    expect(result.days.first.to_h).to include(daily: 8, weekly: 50, monthly: 180, dau_per_mau: 0.04)
    expect(result.days.second.daily).to be_nil
    expect(result.average(:daily)).to eq(10.0)
    expect(result.latest(:monthly)).to eq(200)
  end

  it "asks GA once while cached" do
    2.times { stickiness }

    expect(bodies.size).to eq(1)
  end

  it "reads every day from the stored rolling actives once the whole period is stored, without asking GA" do
    [[1, 8, 50, 160], [2, 10, 55, 170], [3, 12, 60, 200]].each do |day, daily, weekly, monthly|
      Google::Analytics::SiteDayStat.create!(date: Date.new(2026, 10, day), active_1_day_users: daily, active_7_day_users: weekly,
        active_28_day_users: monthly)
    end

    result = stickiness(property: "")

    expect(bodies).to be_empty
    expect(result.days.map(&:daily)).to eq([8, 10, 12])
    expect(result.days.last.to_h).to include(monthly: 200, dau_per_mau: 0.06, dau_per_wau: 0.2, wau_per_mau: 0.3)
  end

  it "asks GA while a day of the period isn't stored" do
    Google::Analytics::SiteDayStat.create!(date: Date.new(2026, 10, 1), active_28_day_users: 180)

    expect(stickiness.days.first.daily).to eq(8)
    expect(bodies.size).to eq(1)
  end

  it "says why when Analytics isn't configured" do
    expect(stickiness(property: "").errors).to eq(["No Analytics property configured (credentials google.analytics_property_id)"])
  end
end
