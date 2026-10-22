# encoding: UTF-8

require "rails_helper"

RSpec.describe MonthAndYearReview do
  let(:today) { Date.new(2026, 10, 12) }

  it "offers the whole months since June 2026, the year so far and the years before" do
    spans = described_class.spans(today: today)

    expect(spans[:months].map(&:key)).to eq(%w[2026-10 2026-09 2026-08 2026-07 2026-06])
    expect(spans[:months].first.label).to eq("October 2026 so far")
    expect(spans[:months].first.compare).to eq("month")
    expect(spans[:months].first.to).to eq(Date.new(2026, 10, 11))
    expect(described_class.spans(today: Date.new(2026, 10, 1))[:months].map(&:key)).to eq(%w[2026-09 2026-08 2026-07 2026-06])
    expect(described_class.span(nil, today: today).key).to eq("2026-09")
    expect(spans[:years].map(&:label)).to eq(["2026 so far"])
    expect(described_class.spans(today: Date.new(2027, 2, 3))[:years].map(&:label)).to eq(["2027 so far", "2026"])
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

    it "sets uploaded AI impressions against the month before once that month was uploaded too" do
      stats = Google::SearchConsole::GenerativeAiStat
      stats.create!(search_type: "Web", date: Date.new(2026, 9, 3), impressions: 12)
      stats.create!(search_type: "Web", date: Date.new(2026, 8, 1), impressions: 4)

      expect(review.figures.find { |figure| figure.label == "AI impressions" }.then { |figure| [figure.current, figure.previous] }).to eq([12, 4])
    end

    it "sets each figure against the month before, leaving unsynced sources empty" do
      figures = review.figures.to_h { |figure| [figure.label, [figure.current, figure.previous]] }

      expect(figures["Views"]).to eq([44, 5])
      expect(figures["Entries published"]).to eq([1, 0])
      expect(figures["Search clicks"]).to eq([nil, nil])
      expect(figures["AI impressions"]).to eq([nil, nil])
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
