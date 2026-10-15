# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncFeedJob do
  include ActiveJob::TestHelper

  it "runs a feed sync" do
    result = SyncResult.new(2, 1, 0, [])
    allow(FeedSyncService).to receive(:call) { result }

    described_class.perform_now

    expect(FeedSyncService).to have_received(:call)
  end
end
