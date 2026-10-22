# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncStats do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-11"}, today: Date.new(2026, 10, 12)) }

  subject(:stats) { described_class.new(period) }

  def sync(at, kind: "feed", status: "succeeded", seconds: 10, **attributes)
    started = Time.zone.parse(at)
    SyncRequest.create!(kind: kind, status: status, created_at: started, started_at: started, finished_at: started + seconds, **attributes)
  end

  before do
    sync("2026-10-10 06:00", created_count: 3, updated_count: 1, unchanged_count: 40)
    sync("2026-10-10 12:00", kind: "analytics", status: "failed", error_messages: ["Timeout after 30 seconds"])
    sync("2026-10-11 06:00", kind: "analytics", status: "failed", error_messages: ["Timeout after 45 seconds"])
    sync("2026-10-11 07:00", seconds: 30, status: "partial", updated_count: 2,
      error_messages: ["Entry https://blog.example.com/post/a: bad date", "Entry https://blog.example.com/post/b: bad date"])
    sync("2026-10-09 06:00")
  end

  it "counts the period's syncs by how they ended" do
    expect(stats.total).to eq(4)
    expect(stats.outcome_counts).to include("succeeded" => 1, "partial" => 1, "failed" => 2, "stalled" => 0)
    expect(stats.daily_by_outcome).to include("succeeded" => [1, 0], "failed" => [1, 1])
    expect(stats.daily_rows).to eq([4, 2])
  end

  it "sums up every kind, failing streaks first" do
    analytics, feed = stats.kinds.first(2)

    expect([analytics.kind, analytics.runs, analytics.failing_streak, analytics.success_rate]).to eq(["analytics", 2, 2, 0.0])
    expect(analytics.last_success).to be_nil
    expect([feed.kind, feed.runs, feed.success_rate, feed.median_seconds, feed.max_seconds, feed.rows]).to eq(["feed", 2, 1.0, 10.0, 30.0, 6])
    expect(feed.last_success).to eq(Time.zone.parse("2026-10-11 07:00:30"))
    expect(stats.kinds.size).to eq(SyncRequest::KINDS.size)
  end

  it "groups errors that differ only in their URLs or numbers" do
    expect(stats.errors.map { |row| [row.message, row.count, row.kinds] }).to eq([
      ["Entry URL: bad date", 2, ["Feed entries"]],
      ["Timeout after # seconds", 2, ["Analytics acquisition, engagement, users & retention"]]
    ])
  end
end
