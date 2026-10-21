# encoding: UTF-8

require "rails_helper"

RSpec.describe Filtering::FeedEntries do
  before do
    FeedEntry.create!(url: "https://blog.example.com/post/a", name: "A", type: "post",
      published_at: Time.zone.parse("2026-10-01"), last_modified_at: Time.zone.parse("2026-10-01"))
    PageView.collection.insert_many([
      {"_id" => "/post/a", "slug" => "/post/a"},
      {"_id" => "/", "slug" => "/"},
      {"_id" => "/tag/css", "slug" => "/tag/css"}
    ])
  end

  def slugs(params)
    Filtering.new(params, fields: [described_class.new]).apply(PageView.all).map(&:slug)
  end

  it "narrows to pages that are feed entries" do
    expect(slugs(only_feed: "true")).to eq(["/post/a"])
  end

  it "leaves every page when not picked" do
    expect(slugs({})).to match_array(["/post/a", "/", "/tag/css"])
  end
end
