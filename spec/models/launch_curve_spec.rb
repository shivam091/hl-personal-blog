# encoding: UTF-8

require "rails_helper"

RSpec.describe LaunchCurve do
  let(:today) { Date.new(2026, 10, 20) }

  def post(slug, published:, views: {})
    entry = FeedEntry.create!(url: "https://blog.example.com#{slug}/", name: slug, type: "post",
      published_at: published.in_time_zone, last_modified_at: published.in_time_zone)
    PageView.collection.insert_one("_id" => slug, "slug" => slug, "url" => entry.url,
      "countriesByDay" => views.to_h { |date, count| [date.iso8601, {"IN" => count}] })
    [PageView.find(slug), entry]
  end

  it "runs a post's views up from publishing, stopping at today" do
    page_view, entry = post("/post/new", published: today - 2, views: {today - 2 => 5, today - 1 => 3, today => 1})

    curve = described_class.new(page_view, entry, today: today)

    expect(curve.dates.first(3)).to eq([today - 2, today - 1, today])
    expect(curve.views.first(4)).to eq([5, 8, 9, nil])
  end

  it "sets it beside the median of earlier posts with a full first month counted" do
    page_view, entry = post("/post/new", published: today - 2)
    start = Date.new(2026, 6, 1)
    post("/post/a", published: start, views: {start => 10, start + 1 => 2})
    post("/post/b", published: start + 10, views: {start + 10 => 20})
    post("/post/c", published: start + 20, views: {start + 20 => 4, start + 21 => 4})
    post("/post/untracked", published: start - 30)

    curve = described_class.new(page_view, entry, today: today)

    expect(curve.typical_count).to eq(3)
    expect(curve.typical.first(3)).to eq([10, 12, 12])
  end

  it "has no typical post with too few to take a median of" do
    page_view, entry = post("/post/new", published: today - 2)
    post("/post/a", published: Date.new(2026, 6, 1), views: {Date.new(2026, 6, 1) => 1})

    expect(described_class.new(page_view, entry, today: today).typical).to be_nil
  end
end
