# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncSitemapJob do
  it "runs a sitemap sync" do
    result = SyncResult.new(2, 1, 0, [])
    allow(SitemapSyncService).to receive(:call) { result }

    described_class.perform_now

    expect(SitemapSyncService).to have_received(:call)
  end
end
