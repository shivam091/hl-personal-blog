# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::SyncJob do
  it "syncs performance over the given days, then sitemaps and URL inspections" do
    [Google::SearchConsole::SyncService, Google::SearchConsole::SitemapSyncService, Google::SearchConsole::UrlInspectionSyncService].each do |service|
      allow(service).to receive(:call) { SyncResult.new(2, 1, 0, []) }
    end

    travel_to(Time.zone.local(2026, 10, 12, 12)) { described_class.perform_now(30) }

    expect(Google::SearchConsole::SyncService).to have_received(:call).with(days: 30, today: Date.new(2026, 10, 12))
    expect(Google::SearchConsole::SitemapSyncService).to have_received(:call)
    expect(Google::SearchConsole::UrlInspectionSyncService).to have_received(:call)
  end

  it "syncs a past range, and only the parts asked for" do
    [Google::SearchConsole::SyncService, Google::SearchConsole::SitemapSyncService, Google::SearchConsole::UrlInspectionSyncService].each do |service|
      allow(service).to receive(:call) { SyncResult.empty }
    end

    described_class.perform_now(10, "2026-09-30", only: ["performance"])

    expect(Google::SearchConsole::SyncService).to have_received(:call).with(days: 10, today: Date.new(2026, 9, 30))
    expect(Google::SearchConsole::SitemapSyncService).not_to have_received(:call)
    expect(Google::SearchConsole::UrlInspectionSyncService).not_to have_received(:call)
  end
end
