# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Crux::SyncService do
  let(:url) { "https://chromeuxreport.googleapis.com/v1/records:queryHistoryRecord" }
  let(:origin) { "https://blog.example.com" }
  let(:requests) { [] }

  def record
    {record: {
      collectionPeriods: [
        {firstDate: {year: 2026, month: 9, day: 6}, lastDate: {year: 2026, month: 10, day: 3}},
        {firstDate: {year: 2026, month: 9, day: 13}, lastDate: {year: 2026, month: 10, day: 10}}
      ],
      metrics: {
        largest_contentful_paint: {
          histogramTimeseries: [{start: 0, end: 2500, densities: [0.81, 0.84]}],
          percentilesTimeseries: {p75s: [2310, 2205]}
        },
        cumulative_layout_shift: {
          histogramTimeseries: [{start: "0.00", end: "0.10", densities: ["NaN", 0.97]}],
          percentilesTimeseries: {p75s: [nil, "0.03"]}
        }
      }
    }}
  end

  def sync
    described_class.call(client: google_key_client, origin: origin)
  end

  it "stores each 28-day window per device, with each metric's p75 and good share" do
    google_stubs.post(url) do |env|
      requests << JSON.parse(env.body)
      [200, {}, record.to_json]
    end

    expect(sync.summary).to eq("6 created, 0 updated, 0 unchanged, 0 failed")
    expect(requests.map { |body| body["formFactor"] }).to eq([nil, "PHONE", "DESKTOP"])
    expect(requests.first).to include("origin" => origin, "collectionPeriodCount" => 40)
    latest = Google::Crux::Stat.find_by(form_factor: "ALL", date: Date.new(2026, 10, 10))
    expect(latest).to have_attributes(
      first_date: Date.new(2026, 9, 13),
      p75: {"lcp" => 2205.0, "cls" => 0.03},
      good: {"lcp" => 0.84, "cls" => 0.97}
    )
    expect(Google::Crux::Stat.find_by(form_factor: "ALL", date: Date.new(2026, 10, 3)).p75).to eq({"lcp" => 2310.0})
  end

  it "skips a device with too few Chrome users, failing only when every device has too few" do
    google_stubs.post(url) do |env|
      if JSON.parse(env.body)["formFactor"] == "DESKTOP"
        [404, {}, {error: {message: "chrome ux report data not found"}}.to_json]
      else
        [200, {}, record.to_json]
      end
    end

    result = sync
    expect(result.errors).to eq([])
    expect(Google::Crux::Stat.distinct(:form_factor)).to contain_exactly("ALL", "PHONE")
  end

  it "says so when no device has enough Chrome users" do
    google_stubs.post(url) { [404, {}, {error: {message: "chrome ux report data not found"}}.to_json] }

    expect(sync.errors).to eq(["CrUX has too few Chrome users of https://blog.example.com to report on"])
  end

  it "reports any other refusal" do
    google_stubs.post(url) { [400, {}, {error: {message: "API key not valid."}}.to_json] }

    expect(sync.errors).to eq(["CrUX: API key not valid."])
  end
end
