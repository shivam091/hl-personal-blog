# encoding: UTF-8

require "rails_helper"

RSpec.describe TopicGaps do
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-12"}, today: Date.new(2026, 10, 13)) }
  let(:date) { Date.new(2026, 10, 5) }

  def query(text, impressions:, clicks: 0, position: 8.0, page: nil)
    Google::SearchConsole::Stat.create!(date: date, query: text, impressions: impressions, clicks: clicks, position: position)
    return unless page

    Google::SearchConsole::Stat.create!(date: date, query: text, page: "https://blog.example.com#{page}", page_path: page,
      impressions: impressions, clicks: clicks, position: position)
  end

  before do
    css = Tag.create!(name: "css")
    FeedEntry.create!(url: "https://blog.example.com/post/css-grid", name: "Mastering CSS Grid", type: "post", tags: [css],
      description: "Lay out anything in two dimensions.", published_at: Time.zone.parse("2026-01-01"), last_modified_at: Time.zone.parse("2026-01-01"))
    FeedEntry.create!(url: "https://blog.example.com/post/flexbox", name: "Flexbox basics", type: "post",
      published_at: Time.zone.parse("2026-02-01"), last_modified_at: Time.zone.parse("2026-02-01"))

    query("css grids tutorial", impressions: 500, page: "/post/css-grid")
    query("css grid", impressions: 300, page: "/")
    query("rust lifetimes", impressions: 200, page: "/post/flexbox")
    query("rust borrow checker", impressions: 100)
    query("flexbox gap", impressions: 80, page: "/tags/css")
    query("flexbox order", impressions: 60, page: "/post/css-grid")
    query("harshal ladhe", impressions: 900, page: "/")
    query("rare query", impressions: 5)
  end

  it "lists searches no entry answers, saying why, most seen first" do
    gaps = described_class.new(period).gaps

    expect(gaps.map { |gap| [gap.query, gap.reason] }).to eq([
      ["css grid", "Only the home page ranks"],
      ["rust lifetimes", "No entry covers it"],
      ["rust borrow checker", "No entry covers it"],
      ["flexbox gap", "Only a listing page ranks"],
      ["flexbox order", "Ranks with a loosely matched entry"]
    ])
    expect(gaps.first.closest.name).to eq("Mastering CSS Grid")
  end

  it "groups gaps under the word they share, the most seen topic first" do
    topics = described_class.new(period).topics

    expect(topics.map { |topic| [topic.word, topic.impressions, topic.gaps.map(&:query)] }).to eq([
      ["css", 300, ["css grid"]],
      ["rust", 300, ["rust lifetimes", "rust borrow checker"]],
      ["flexbox", 140, ["flexbox gap", "flexbox order"]]
    ])
  end

  it "takes a country's impressions from the queries Search Console split by country" do
    Google::SearchConsole::QueryCountryStat.create!(date: date, query: "rust lifetimes", country: "IN", impressions: 40, clicks: 0, position: 9.0)
    Google::SearchConsole::QueryCountryStat.create!(date: date, query: "css grid", country: "US", impressions: 40, clicks: 0, position: 9.0)

    gaps = described_class.new(period, country: "IN", min_impressions: 10).gaps

    expect(gaps.map { |gap| [gap.query, gap.impressions] }).to eq([["rust lifetimes", 40]])
  end

  it "exports gaps and empty site searches as CSV" do
    Google::Analytics::SearchTermStat.create!(date: date, search_term: "webgl", event_name: "search_no_results", event_count: 7)
    Google::Analytics::SearchTermStat.create!(date: date, search_term: "webgl", event_name: "view_search_results", event_count: 3)
    gaps = described_class.new(period, min_impressions: 100)

    expect(CSV.parse(gaps.to_csv).drop(1).map { |row| row.first(2) }).to eq([["css", "css grid"], ["rust", "rust lifetimes"], ["rust", "rust borrow checker"]])
    expect(CSV.parse(gaps.to_csv("site-search"))).to eq([["Search term", "Searches finding nothing", "Searches"], ["webgl", "7", "10"]])
  end
end
