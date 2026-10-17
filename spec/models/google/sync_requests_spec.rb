# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncRequest, "for Google's syncs" do
  it "queues a range of days for a daily report" do
    request = described_class.enqueue("search_console_performance", from_date: Date.new(2026, 10, 1), to_date: Date.new(2026, 10, 10))

    expect(request).to have_attributes(status: "queued", trigger: "admin", days: 10)
    expect(Google::SearchConsole::SyncJob).to have_been_enqueued.with(10, "2026-10-10", only: ["performance"], request_id: request.id.to_s)
  end

  it "resyncs the same batch of URL inspections" do
    original = described_class.create!(kind: "url_inspections", trigger: "rake", status: "failed", limit: 25)

    resync = original.resync

    expect(resync).to have_attributes(kind: "url_inspections", trigger: "resync", limit: 25)
    expect(Google::SearchConsole::SyncJob).to have_been_enqueued.with(only: ["url_inspections"], limit: 25, request_id: resync.id.to_s)
  end

  it "records each part of a Search Console run as its own request" do
    [Google::SearchConsole::SyncService, Google::SearchConsole::SitemapSyncService, Google::SearchConsole::UrlInspectionSyncService].each do |service|
      allow(service).to receive(:call) { SyncResult.new(1, 0, 0, []) }
    end

    travel_to(Time.zone.local(2026, 10, 12, 12)) { Google::SearchConsole::SyncJob.perform_now(7) }

    expect(described_class.pluck(:kind)).to contain_exactly("search_console_performance", "search_console_sitemaps", "url_inspections")
    expect(described_class.find_by(kind: "search_console_performance"))
      .to have_attributes(trigger: "job", status: "succeeded", from_date: Date.new(2026, 10, 6), to_date: Date.new(2026, 10, 12))
    expect(described_class.find_by(kind: "url_inspections").limit).to eq(100)
  end

  it "updates the request an Analytics job was enqueued for" do
    allow(Google::Analytics::SyncService).to receive(:call) { SyncResult.new(0, 0, 0, ["Analytics: quota exceeded"]) }
    request = described_class.enqueue("analytics", from_date: Date.new(2026, 10, 6), to_date: Date.new(2026, 10, 12))

    Google::Analytics::SyncJob.perform_now(7, "2026-10-12", request_id: request.id.to_s)

    expect(described_class.count).to eq(1)
    expect(request.reload).to have_attributes(status: "failed", error_messages: ["Analytics: quota exceeded"])
  end
end
