# encoding: UTF-8

require "rails_helper"

RSpec.describe LaunchReport do
  let(:today) { Date.new(2026, 10, 20) }

  def post(slug, published:, views: {}, likes: {}, clicks: {}, analytics: {})
    entry = FeedEntry.create!(url: "https://blog.example.com#{slug}/", name: slug, type: "post",
      published_at: published.in_time_zone, last_modified_at: published.in_time_zone)
    PageView.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => views.to_h { |date, count| [date.iso8601, {"IN" => count}] })
    PageLike.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => likes.to_h { |date, count| [date.iso8601, {"IN" => count}] })
    clicks.each do |date, count|
      Google::SearchConsole::Stat.create!(date: date, page: entry.url, page_path: "#{slug}/", clicks: count, impressions: count * 10, position: 5.0)
    end
    analytics.each { |date, count| Google::Analytics::Stat.create!(date: date, page_path: slug, views: count) }
    entry
  end

  it "sets each measure over the entry's first days beside the median of earlier entries at the same age" do
    entry = post("/post/new", published: today - 7, views: {today - 7 => 30, today - 1 => 30, today => 50}, likes: {today - 6 => 2},
      clicks: {today - 6 => 4}, analytics: {today - 7 => 25})
    start = Date.new(2026, 7, 1)
    [10, 20, 30].each_with_index do |count, index|
      published = start + index * 10
      post("/post/old#{index}", published: published, views: {published => count, published + 7 => 100}, likes: {published => 1},
        clicks: {published => count / 10}, analytics: {published => count})
    end
    Google::SearchConsole::Stat.create!(date: today, page: "https://blog.example.com/", page_path: "/", clicks: 0, impressions: 0)
    Google::Analytics::Stat.create!(date: today, page_path: "/", views: 0)

    report = described_class.new(entry, 7, today: today)

    expect(report.days).to eq((today - 7)..(today - 1))
    expect(report.measures.map { |measure| [measure.label, measure.value, measure.typical, measure.settled] }).to eq([
      ["Views", 60, 20, true], ["Likes", 2, 1, true], ["Search clicks", 4, 2, true], ["Analytics views", 25, 20, true]
    ])
    expect(report.measures.first.verdict).to eq(:above)
    expect(report.summary).to eq("ahead of the typical entry")
  end

  it "has nothing to compare with when too few earlier entries had a full first month" do
    entry = post("/post/new", published: today - 7, views: {today - 7 => 3})

    report = described_class.new(entry, 7, today: today)

    expect(report.measures.map(&:typical)).to all(be_nil)
    expect(report.measures.drop(2).map(&:settled)).to eq([false, false])
    expect(report.summary).to eq("too few earlier entries to compare with")
  end
end
