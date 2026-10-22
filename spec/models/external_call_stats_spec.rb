# encoding: UTF-8

require "rails_helper"

RSpec.describe ExternalCallStats do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-11"}, today: Date.new(2026, 10, 12)) }

  subject(:stats) { described_class.new(period) }

  def call(at, service: "Search Console", status: 200, duration_ms: 100, **attributes)
    ExternalCall.create!(service: service, http_method: "GET", url: "https://example.com/", status: status, duration_ms: duration_ms,
      created_at: Time.zone.parse(at), **attributes)
  end

  before do
    call("2026-10-10 09:00", duration_ms: 200)
    call("2026-10-10 10:00", status: 429, duration_ms: 50)
    call("2026-10-11 10:00", status: nil, duration_ms: 30_000, error: "execution expired")
    call("2026-10-11 11:00", service: "PageSpeed Insights", duration_ms: 9_000)
    call("2026-10-09 10:00", status: 500)
  end

  it "reads only the period's calls and times them" do
    expect([stats.total, stats.failed]).to eq([4, 2])
    expect(stats.median_ms).to eq(200)
    expect(stats.p95_ms).to eq(30_000)
  end

  it "splits each day by service and counts its failures" do
    expect(stats.daily_by_service).to eq("Search Console" => [2, 1], "PageSpeed Insights" => [0, 1])
    expect(stats.daily_failed).to eq([1, 1])
  end

  it "sums up each service, busiest first" do
    console, speed = stats.services

    expect([console.service, console.calls, console.failed, console.failure_rate]).to eq(["Search Console", 3, 2, 2 / 3.0])
    expect(console.last_failure).to eq(Time.zone.parse("2026-10-11 10:00"))
    expect([speed.service, speed.failed, speed.last_failure]).to eq(["PageSpeed Insights", 0, nil])
  end

  it "groups failures by message, or by status when none came back" do
    expect(stats.errors.map { |row| [row.service, row.error, row.count] }).to eq([
      ["Search Console", "HTTP 429", 1], ["Search Console", "execution expired", 1]
    ])
  end
end
