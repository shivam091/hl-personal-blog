# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::CohortService do
  let(:url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  # A Wednesday, so the last complete week starts on Sunday 4 October.
  let(:today) { Date.new(2026, 10, 14) }
  let(:bodies) { [] }

  def cohorts(property: 123456789, **filters)
    described_class.new(property: property, client: google_client, cache: cache).call(today: today, **filters)
  end

  before do
    google_stubs.post(url) do |env|
      bodies << JSON.parse(env.body)
      rows = [
        ["2026-09-27", "0000", 40, 40],
        ["2026-09-27", "0001", 6, 40],
        ["2026-10-04", "0000", 25, 25]
      ]
      [200, {}, {
        rows: rows.map do |name, week, active, total|
          {
            dimensionValues: [{value: name}, {value: week}],
            metricValues: [{value: active.to_s}, {value: total.to_s}]
          }
        end,
        propertyQuota: {tokensPerDay: {consumed: 3, remaining: 199_000}}}.to_json
      ]
    end
  end

  it "asks for twelve weekly cohorts by first visit, ending with the last complete week" do
    cohorts

    spec = bodies.first["cohortSpec"]
    expect(spec["cohorts"].size).to eq(12)
    expect(spec["cohorts"].last).to eq({
      "name" => "2026-10-04",
      "dimension" => "firstSessionDate",
      "dateRange" => {"startDate" => "2026-10-04", "endDate" => "2026-10-10"}
    })
    expect(spec["cohortsRange"]).to eq({"granularity" => "WEEKLY", "startOffset" => 0, "endOffset" => 11})
    expect(Google::Analytics::Quota.find_by(category: "core").quota.dig("tokensPerDay", "remaining")).to eq(199_000)
  end

  it "gives each cohort's share back each finished week, leaving the rest out" do
    result = cohorts

    september = result.cohorts.find { |cohort| cohort.start == Date.new(2026, 9, 27) }
    expect(september.users).to eq(40)
    expect(september.active).to eq({0 => 40, 1 => 6})
    expect(september.retention(1)).to eq(0.15)
    expect(september.retention(2)).to be_nil
    expect(result.cohorts.last.active).to eq({0 => 25})
  end

  it "asks GA once while cached" do
    2.times { cohorts }

    expect(bodies.size).to eq(1)
  end

  it "asks for the weeks, country and device picked, cached apart from the rest" do
    result = cohorts(weeks: "4", country: "in", device: "mobile")
    cohorts

    expect(result.weeks).to eq(4)
    expect(bodies.size).to eq(2)
    spec = bodies.first["cohortSpec"]
    expect(spec["cohorts"].size).to eq(4)
    expect(spec["cohortsRange"]["endOffset"]).to eq(3)
    filters = bodies.first.dig("dimensionFilter", "andGroup", "expressions").map { |expression| expression["filter"] }
    expect(filters.map { |filter| [filter["fieldName"], filter.dig("stringFilter", "value")] })
      .to eq([["hostName", Google::Analytics::SyncService::HOSTNAME], %w[countryId IN], %w[deviceCategory mobile]])
  end

  it "reads a span or device not offered as the default" do
    result = cohorts(weeks: "7", device: "toaster")

    expect(result.weeks).to eq(12)
    expect(bodies.first.dig("dimensionFilter", "andGroup", "expressions").size).to eq(1)
  end

  it "exports each cohort's readers and share back per week" do
    csv = CSV.parse(described_class.to_csv(cohorts(weeks: 4)))

    expect(csv.first).to eq(["First visit week", "Readers", "Week 1 back", "Week 1 share", "Week 2 back", "Week 2 share", "Week 3 back", "Week 3 share"])
    expect(csv.find { |row| row.first == "2026-09-27" }).to eq(["2026-09-27", "40", "6", "0.15", nil, nil, nil, nil])
  end

  it "says why when Analytics isn't configured" do
    expect(cohorts(property: "").errors).to eq(["No Analytics property configured (credentials google.analytics_property_id)"])
  end
end
