# encoding: UTF-8

require "rails_helper"

RSpec.describe RequestStats do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-11"}, today: Date.new(2026, 10, 12)) }

  subject(:stats) { described_class.new(period) }

  def log(at, path: "/", status: 200, seconds: 0.1, **attributes)
    RequestLog.create!(uri: "https://admin.example.com#{path}", request_method: "GET", status: status, elapsed_time: seconds,
      created_at: Time.zone.parse(at), **attributes)
  end

  before do
    RequestLog.delete_all
    log("2026-10-10 09:15", path: "/page-views/%2Fpost%2Fa", seconds: 0.2, memory_usage: 204_800, cpu_usage: 40.0,
      ip_info: {"country_code" => "in"}, user_agent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 Chrome/141.0 Safari/537.36")
    log("2026-10-10 09:40", path: "/page-views/%2Fpost%2Fb?sort=views", seconds: 1.0, memory_usage: 102_400, cpu_usage: 20.0,
      user_agent: "Googlebot/2.1")
    log("2026-10-11 22:05", path: "/crawled-pages", status: 500, seconds: 0.4,
      exception: {"class" => "Mongo::Error::SocketError", "message" => "timed out"})
    log("2026-10-11 22:06", path: "/session", status: 422)
    log("2026-10-11 22:07", path: "/", status: 200).update!(uri: "http://localhost:3000/")
    log("2026-10-09 10:00", path: "/before")
  end

  it "reads only the period's logs, leaving development's out" do
    expect(stats.total).to eq(4)
    expect(stats.count("5xx")).to eq(1)
    expect(stats.count("4xx")).to eq(1)
  end

  it "splits each day by status class and times it" do
    expect(stats.daily_by_status).to eq("2xx" => [2, 0], "3xx" => [0, 0], "4xx" => [0, 1], "5xx" => [0, 1])
    expect(stats.daily_timings).to eq(median: [200, 100], p95: [1000, 400])
    expect(stats.median_ms.round).to eq(200)
    expect(stats.p95_ms.round).to eq(1000)
  end

  it "groups pages with an id into one row, slowest tail first" do
    rows = stats.slowest_paths

    expect(rows.map { |row| [row.path, row.requests, row.p95_ms.round, row.errors] }).to eq([
      ["/page-views/:id", 2, 1000, 0], ["/crawled-pages", 1, 400, 1], ["/session", 1, 100, 0]
    ])
  end

  it "groups exceptions by class with the latest one" do
    row = stats.exceptions.sole

    expect([row.name, row.count, row.last.exception["message"]]).to eq(["Mongo::Error::SocketError", 1, "timed out"])
  end

  it "places requests and names their clients" do
    expect(stats.countries).to eq("IN" => 1, "ZZ" => 3)
    expect(stats.agents).to eq("Chrome on Linux" => 1, "Googlebot" => 1, "No user agent" => 2)
    expect(stats.bots).to eq(3)
  end

  it "counts requests by weekday and hour, and the server's daily highs" do
    expect(stats.hours[5][9]).to eq(2)
    expect(stats.hours[6][22]).to eq(2)
    expect(stats.daily_memory_mb).to eq([200, 0])
    expect(stats.daily_cpu).to eq([30.0, 0.0])
  end
end
