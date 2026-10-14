# encoding: UTF-8

require "rails_helper"

RSpec.describe DashboardHelper, type: :helper do
  it "groups referrers by host as the frontend stores them, dots swapped for underscores" do
    referrers = {
      "google_com" => 1,
      "www_google_co_in" => 1,
      "x_com" => 2,
      "t_co" => 3,
      "news_ycombinator_com" => 4,
      "l_facebook_com" => 5,
      "direct" => 6,
      "internal" => 7,
      "microsoft_com" => 8
    }

    expect(helper.referrer_groups(referrers)).to eq("Search" => 2, "Social" => 14, "Direct" => 6, "Internal" => 7, "Other sites" => 8)
  end

  it "shows stored referrer keys as hosts" do
    expect(helper.referrer_hosts("google_com" => 2, "google.com" => 1, "direct" => 3)).to eq("google.com" => 3, "direct" => 3)
  end

  it "says when views and likes were first counted, only for a period reaching back before then" do
    period = Period.new({from: "2026-09-01", to: "2026-10-12"}, today: Date.new(2026, 10, 12))
    views, likes = Date.new(2026, 9, 15), Date.new(2026, 10, 1)

    expect(helper.counted_since_note(period, views: views, likes: likes))
      .to eq("Page views are counted from #{helper.l(views)} and likes from #{helper.l(likes)}, so earlier days in this period have none.")
    expect(helper.counted_since_note(period, views: Date.new(2026, 8, 1), likes: likes))
      .to eq("Page likes are counted from #{helper.l(likes)}, so earlier days in this period have none.")
    expect(helper.counted_since_note(period, views: Date.new(2026, 8, 1), likes: nil)).to be_nil
  end

  it "says when any other figure was first counted the same way, with why when there's one" do
    counted = CountedSince.new(date: Date.new(2026, 10, 20), what: "Searches", why: "when the blog's search began sending them")

    expect(helper.counted_from_note(Date.new(2026, 10, 1), counted))
      .to eq("Searches are counted from 20 Oct, 2026, when the blog's search began sending them, so earlier days in this period have none.")
    expect(helper.counted_from_note(Date.new(2026, 10, 1), counted.dup.tap { |plain| plain.why = nil }))
      .to eq("Searches are counted from 20 Oct, 2026, so earlier days in this period have none.")
    expect(helper.counted_from_note(Date.new(2026, 10, 20), counted)).to be_nil
    expect(helper.counted_from_note(Date.new(2026, 10, 1), nil)).to be_nil
  end
end
