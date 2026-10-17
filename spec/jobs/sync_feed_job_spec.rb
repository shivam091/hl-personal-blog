# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncFeedJob do
  include ActiveJob::TestHelper

  it "runs a feed sync" do
    result = SyncResult.new(2, 1, 0, [])
    allow(FeedSyncService).to receive(:call) { result }
    allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new) {
      instance_double(Google::SearchConsole::UrlInspectionSyncService, inspect_new_entries: SyncResult.empty)
    }

    described_class.perform_now

    expect(FeedSyncService).to have_received(:call)
  end

  it "inspects new entries once the sync has created any" do
    inspection = instance_double(Google::SearchConsole::UrlInspectionSyncService, inspect_new_entries: SyncResult.empty)
    allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new) { inspection }
    allow(FeedSyncService).to receive(:call) { SyncResult.new(1, 0, 0, []) }

    described_class.perform_now

    expect(inspection).to have_received(:inspect_new_entries)
    expect(SyncRequest.where(kind: "url_inspections").count).to eq(1)
  end

  it "resubmits the sitemap once the sync has created any entries" do
    allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new) {
      instance_double(Google::SearchConsole::UrlInspectionSyncService, inspect_new_entries: SyncResult.empty)
    }
    allow(FeedSyncService).to receive(:call) { SyncResult.new(1, 0, 0, []) }

    expect { described_class.perform_now }.to have_enqueued_job(Google::SearchConsole::SitemapSubmitJob)
  end

  it "marks new entries on GA's charts once the sync has created any" do
    allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new) {
      instance_double(Google::SearchConsole::UrlInspectionSyncService, inspect_new_entries: SyncResult.empty)
    }
    allow(FeedSyncService).to receive(:call) { SyncResult.new(1, 0, 0, []) }

    expect { described_class.perform_now }.to have_enqueued_job(Google::Analytics::AnnotationJob)
  end

  it "doesn't inspect when nothing new was synced" do
    allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new)
    allow(FeedSyncService).to receive(:call) { SyncResult.new(0, 2, 5, []) }

    described_class.perform_now

    expect(Google::SearchConsole::UrlInspectionSyncService).not_to have_received(:new)
  end
end
