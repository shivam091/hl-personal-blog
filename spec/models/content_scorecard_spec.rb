# encoding: UTF-8

require "rails_helper"

RSpec.describe ContentScorecard do
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: Date.new(2026, 10, 13)) }

  subject(:scorecard) do
    described_class.new(ContentStats.new(BlogStats.new(period), search: Google::SearchConsole::Summary.new(period)))
  end

  def entry(path)
    FeedEntry.create!(url: "https://blog.example.com#{path}", name: path, type: "post",
      published_at: Time.zone.parse("2026-01-01"), last_modified_at: Time.zone.parse("2026-01-01"))
  end

  def views(path, count)
    PageView.collection.insert_one("_id" => path, "slug" => path, "countriesByDay" => {"2026-10-07" => {"IN" => count}})
  end

  def search(path, clicks:, impressions:)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 7), page: "https://blog.example.com#{path}", page_path: path,
      clicks: clicks, impressions: impressions, position: 5.0)
  end

  before do
    %w[/post/best /post/seen /post/quiet].each { |path| entry(path) }
    views("/post/best", 300)
    views("/post/seen", 100)
    views("/post/quiet", 10)
    search("/post/best", clicks: 30, impressions: 100)
    search("/post/seen", clicks: 1, impressions: 900)
    Google::PageSpeed::Result.create!(url: "https://blog.example.com/post/best", page_path: "/post/best", strategy: "mobile", performance: 0.9)
  end

  it "scores each entry by its average place on each measure, a missing one counting as middling" do
    rows = scorecard.rows

    # Seen often but clicked rarely, /post/seen is known to be weak in
    # search, where /post/quiet has no figures to judge.
    expect(rows.map { |row| row.item.path }).to eq(%w[/post/best /post/quiet /post/seen])
    best = rows.first
    expect(best.values).to include(views: 300, clicks: 30, ctr: 0.3, performance: 0.9)
    # Both well-read entries have no likes, so they tie halfway.
    expect(best.ranks).to eq(views: 1.0, like_rate: 0.5, clicks: 1.0, ctr: 1.0, performance: 1.0)
    expect(best.score).to eq(5.5 / 7)
    expect(rows.second.ranks).to eq(views: 0.0)
  end

  it "puts entries seen often in search but weak overall first for potential" do
    rows = scorecard.rows(sort: "potential")

    expect(rows.first.item.path).to eq("/post/seen")
    expect(rows.first.potential).to eq(1 - 2.5 / 7)
    expect(rows.find { |row| row.item.path == "/post/quiet" }.potential).to be_nil
  end
end
