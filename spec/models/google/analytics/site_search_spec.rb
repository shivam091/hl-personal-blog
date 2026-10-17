# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::SiteSearch do
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }

  def searched(term, event, count, date: Date.new(2026, 10, 8))
    Google::Analytics::SearchTermStat.create!(
      date: date,
      search_term: term,
      event_name: event,
      event_count: count
    )
  end

  before do
    searched("grid", "view_search_results", 8)
    searched("grid", "search_no_results", 2)
    searched("subgrid", "search_no_results", 3)
    searched("flexbox", "view_search_results", 4)
    # Outside the period.
    searched("old", "search_no_results", 9, date: Date.new(2026, 9, 1))
  end

  subject(:search) { described_class.new(period) }

  it "adds up each term's searches, and those that found nothing" do
    expect(search.top_terms.map(&:to_h)).to eq([
      {term: "grid", searches: 10, not_found: 2},
      {term: "flexbox", searches: 4, not_found: 0},
      {term: "subgrid", searches: 3, not_found: 3}
    ])
    expect(search.searches).to eq(17)
    expect(search.not_found_share).to eq(5 / 17.0)
  end

  it "lists terms that found nothing, most often first" do
    expect(search.not_found_terms.map { |row| [row.term, row.not_found] }).to eq([
      ["subgrid", 3],
      ["grid", 2]
    ])
  end
end
