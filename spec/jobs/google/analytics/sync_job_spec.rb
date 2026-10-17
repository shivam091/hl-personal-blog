# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::SyncJob do
  it "runs a sync over the given days" do
    allow(Google::Analytics::SyncService).to receive(:call) { SyncResult.new(2, 1, 0, []) }

    travel_to(Time.zone.local(2026, 10, 12, 12)) { described_class.perform_now(30) }

    expect(Google::Analytics::SyncService).to have_received(:call).with(days: 30, today: Date.new(2026, 10, 12))
  end

  it "syncs a range ending in the past" do
    allow(Google::Analytics::SyncService).to receive(:call) { SyncResult.empty }

    described_class.perform_now(7, "2026-09-30")

    expect(Google::Analytics::SyncService).to have_received(:call).with(days: 7, today: Date.new(2026, 9, 30))
  end
end
