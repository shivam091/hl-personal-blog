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

  it "asks for the Generative AI report again once its upload stops well short of today, without failing the syncs" do
    sync("feed", "succeeded")
    stats = Google::SearchConsole::GenerativeAiStat
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 10), impressions: 3)

    expect(described_class.new.stale_ai_upload).to be_nil

    stats.where(date: Date.new(2026, 10, 10)).update_all(date: Date.new(2026, 10, 9))
    stale = described_class.new

    expect(stale.stale_ai_upload.last_day).to eq(Date.new(2026, 10, 9))
    expect(stale).to be_needs_a_look
    expect(stale).to be_healthy
  end

  it "says nothing of the Generative AI report before anything was uploaded" do
    sync("feed", "succeeded")

    expect(digest.stale_ai_upload).to be_nil
    expect(digest).not_to be_needs_a_look
  end
end
