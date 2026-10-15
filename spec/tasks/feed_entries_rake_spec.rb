# encoding: UTF-8

require "rails_helper"
require "rake"

RSpec.describe "feed_entries rake tasks" do
  before(:all) { Rails.application.load_tasks if Rake::Task.tasks.empty? }

  def run(name, *args)
    task = Rake::Task[name]
    task.reenable
    task.invoke(*args)
  end

  it "records a sync as started by a rake task" do
    allow(FeedSyncService).to receive(:call) { SyncResult.new(2, 0, 1, []) }

    expect { run("feed_entries:sync_feed") }.to output(/Feed sync: 2 created/).to_stdout

    expect(SyncRequest.first).to have_attributes(kind: "feed", trigger: "rake", status: "succeeded", created_count: 2)
  end

  it "records an export under the page's own export URL" do
    expect { run("feed_entries:export") }.to output.to_stdout

    expect(ExportRequest.first).to have_attributes(section: "Feed entries", trigger: "rake", filename: "(stdout)", path: "/feed-entries.csv")
  end
end
