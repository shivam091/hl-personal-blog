# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncRequestsHelper, type: :helper do
  before { stub_sync_kinds }

  def last_sync_line(kind)
    Nokogiri::HTML5.fragment(helper.last_sync_status(kind)).at_css("#last-sync")
  end

  it "dates a page's data from the last sync that brought any in, and flags a newer failure" do
    travel_to(Time.zone.local(2026, 10, 12, 12)) do
      SyncRequest.create!(kind: "posts", status: "succeeded", finished_at: 3.hours.ago, created_at: 3.hours.ago)
      SyncRequest.create!(kind: "posts", status: "failed", finished_at: 1.hour.ago, created_at: 1.hour.ago)

      line = last_sync_line("posts")

      expect(line.text.squish).to include("Last synced 12 Oct, 2026 09:00", "(about 3 hours ago)", "Last sync failed")
      expect(line.at_css("a")["href"]).to eq(sync_requests_path(section: "posts"))
    end
  end

  it "flags a sync in progress, and says when none is recorded" do
    expect(last_sync_line("posts").text).to include("No sync recorded yet")

    SyncRequest.create!(kind: "posts", status: "running")

    expect(last_sync_line("posts").text).to include("Sync in progress")
  end

  it "says what a sync covered" do
    expect(helper.sync_scope(SyncRequest.new(kind: "posts", from_date: Date.new(2026, 10, 1), to_date: Date.new(2026, 10, 7))))
      .to eq("1 Oct, 2026 – 7 Oct, 2026 (7 days)")
    expect(helper.sync_scope(SyncRequest.new(kind: "pages", limit: 100))).to eq("Next 100 pages")
    expect(helper.sync_scope(SyncRequest.new(kind: "posts"))).to eq("Everything Blog feed holds")
  end
end
