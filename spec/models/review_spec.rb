# encoding: UTF-8

require "rails_helper"

RSpec.describe Review do
  let(:today) { Date.new(2026, 10, 12) }

  it "offers the last twelve whole months, the year so far and the years before" do
    spans = described_class.spans(today: today)

    expect(spans[:months].map(&:key).first(2)).to eq(%w[2026-09 2026-08])
    expect(spans[:months].size).to eq(12)
    expect(spans[:years].map(&:label)).to eq(["2026 so far", "2025", "2024", "2023"])
    expect(spans[:years].first.compare).to eq("year")
    expect(described_class.span("nonsense", today: today).key).to eq("2026-09")
  end

  describe "a month's figures" do
    let(:period) { described_class.span("2026-09", today: today).period }

    subject(:review) do
      described_class.new(BlogStats.new(period), search: Google::SearchConsole::Summary.new(period), analytics: Google::Analytics::Summary.new(period))
    end

    before do
      PageView.collection.insert_many([
        {"_id" => "/post/a", "slug" => "/post/a", "countriesByDay" => {"2026-09-10" => {"IN" => 30}, "2026-08-10" => {"IN" => 5}}},
        {"_id" => "/post/b", "slug" => "/post/b", "countriesByDay" => {"2026-09-12" => {"US" => 10, "unknown" => 4}}}
      ])
      FeedEntry.create!(url: "https://blog.example.com/post/a", name: "A post", type: "post",
        published_at: Time.zone.parse("2026-09-01"), last_modified_at: Time.zone.parse("2026-09-01"))
    end

    it "sets each figure against the month before, leaving unsynced sources empty" do
      figures = review.figures.to_h { |figure| [figure.label, [figure.current, figure.previous]] }

      expect(figures["Views"]).to eq([44, 5])
      expect(figures["Entries published"]).to eq([1, 0])
      expect(figures["Search clicks"]).to eq([nil, nil])
      expect(period.previous.from).to eq(Date.new(2026, 8, 1))
    end

    it "lists the most read pages, what was published, top countries and movers" do
      expect(review.top_pages).to eq([["/post/a", 30], ["/post/b", 14]])
      expect(review.names["/post/a"]).to eq("A post")
      expect(review.new_entries.map { |entry, views| [entry.name, views] }).to eq([["A post", 30]])
      expect(review.top_countries).to eq([["IN", 30], ["US", 10]])
      expect(review.movers.first.map(&:first)).to eq(["/post/a"])
    end
  end
end
