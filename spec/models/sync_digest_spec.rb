# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncDigest do
  let(:now) { Time.zone.local(2026, 10, 20, 9) }

  def sync(kind, status, at: now - 1.hour, **attributes)
    SyncRequest.create!(
      kind: kind,
      status: status,
      trigger: "rake",
      created_at: at,
      updated_at: at,
      **attributes
    )
  end

  # Throughout, since whether a run has stalled depends on the time.
  around { |example| travel_to(now) { example.run } }

  let(:digest) { described_class.new }

  it "covers only the last 24 hours" do
    sync("feed", "succeeded")
    sync("feed", "failed", at: now - 25.hours)

    expect(digest.requests.size).to eq(1)
    expect(digest.summary).to eq("the 1 sync succeeded")
    expect(digest).to be_healthy
  end

  it "counts what went wrong, a lost run as stalled" do
    sync("analytics", "succeeded")
    sync("analytics", "failed", error_count: 1, error_messages: ["boom"])
    sync("url_inspections", "partial", error_count: 4)
    sync("sitemap", "running", at: now - 2.hours)
    sync("feed", "queued", at: now - 1.minute)

    expect(digest.summary).to eq("1 failed, 1 with errors, 1 stalled, and 1 still running of 5")
    expect(digest.problems.map(&:kind)).to eq(%w[sitemap analytics url_inspections])
    expect(digest).not_to be_healthy
  end

  it "flags a day with no syncs, since the schedule itself may have stopped" do
    expect(digest.summary).to eq("no syncs ran in the last 24 hours")
    expect(digest).not_to be_healthy
  end
end
