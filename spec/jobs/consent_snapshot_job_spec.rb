# encoding: UTF-8

require "rails_helper"

RSpec.describe ConsentSnapshotJob, type: :job do
  let(:today) { Date.new(2026, 10, 13) }

  before do
    PageView.collection.insert_one("_id" => "/a", "slug" => "/a", "countriesByDay" => {"2026-10-12" => {"IN" => 100}},
      "consentByDay" => {"2026-10-12" => {"granted" => 60, "denied" => 40}})
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 12), page_path: "/a", views: 55)
  end

  it "snapshots the last three days up to yesterday, leaving GA's figure out of a day it hasn't synced" do
    expect(described_class.perform_now(today: today)).to eq(3)

    expect(ConsentSnapshot.pluck(:day).sort).to eq(%w[2026-10-10 2026-10-11 2026-10-12])
    expect(ConsentSnapshot.find_by(day: "2026-10-12")).to have_attributes(first_party: 100, analytics: 55, gap: 45, denied: 40)
    expect(ConsentSnapshot.find_by(day: "2026-10-11").analytics).to be_nil
  end

  it "is harmless to run again" do
    2.times { described_class.perform_now(today: today) }

    expect(ConsentSnapshot.count).to eq(3)
  end

  it "snapshots a span asked for, as a backfill does" do
    expect(described_class.perform_now(today: today, from: Date.new(2026, 10, 1), to: Date.new(2026, 10, 12))).to eq(12)
  end

  it "records each run as a sync, so a failed night shows with the others" do
    described_class.perform_now(today: today)
    described_class.perform_now(today: today, from: Date.new(2026, 10, 11), to: Date.new(2026, 10, 12), trigger: "rake")

    first, second = SyncRequest.where(kind: "consent_snapshot").order(created_at: :asc).to_a
    expect(first).to have_attributes(status: "succeeded", trigger: "job", from_date: Date.new(2026, 10, 10), to_date: Date.new(2026, 10, 12),
      created_count: 3, updated_count: 0)
    expect(second).to have_attributes(trigger: "rake", created_count: 0, updated_count: 2)
  end

  it "records a run that fails, and still raises" do
    allow(ConsentSnapshot).to receive(:record).and_raise(Mongo::Error::SocketError, "lost")

    expect { described_class.perform_now(today: today) }.to raise_error(Mongo::Error::SocketError)
    expect(SyncRequest.find_by(kind: "consent_snapshot")).to have_attributes(status: "failed", error_messages: ["Mongo::Error::SocketError: lost"])
  end

  it "runs again as the request asked, from Sync requests" do
    request = SyncRequest.create!(kind: "consent_snapshot", from_date: Date.new(2026, 10, 11), to_date: Date.new(2026, 10, 12))

    expect { request.resync }.to have_enqueued_job(described_class).with(from: Date.new(2026, 10, 11), to: Date.new(2026, 10, 12), request_id: anything)
  end
end
