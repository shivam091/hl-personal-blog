# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::AiGaps do
  let(:period) { Period.new({from: "2026-10-05", to: "2026-10-11"}, today: Date.new(2026, 10, 12)) }

  subject(:gaps) { described_class.new(Google::SearchConsole::GenerativeAiSummary.new(period)) }

  def ai_page(path, impressions)
    Google::SearchConsole::GenerativeAiRow.create!(search_type: "Web", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30),
      breakdown: "pages", label: "https://blog.example.com#{path}", impressions: impressions)
  end

  def search_page(path, clicks:, impressions:, date: Date.new(2026, 9, 10))
    Google::SearchConsole::Stat.create!(search_type: "web", date: date, page: "https://blog.example.com#{path}", page_path: path,
      clicks: clicks, impressions: impressions, position: 5.0)
  end

  before { Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 9, 1), impressions: 1) }

  it "has nothing to say before an upload with pages" do
    Google::SearchConsole::GenerativeAiRow.delete_all

    expect([gaps.any?, gaps.shown_not_clicked, gaps.missing_from_ai]).to eq([false, [], []])
  end

  it "ranks pages AI answers show often by how few search clicks they got over the upload's own days" do
    ai_page("/post/cited", 40)
    ai_page("/post/clicked", 20)
    ai_page("/post/stray", 3)
    search_page("/post/cited", clicks: 1, impressions: 90)
    search_page("/post/clicked", clicks: 15, impressions: 60)
    # Outside the upload's range, to show search's figures are taken over
    # the same days as the upload's.
    search_page("/post/cited", clicks: 50, impressions: 500, date: Date.new(2026, 10, 6))

    expect(gaps.shown_not_clicked.map { |row| [row.page_path, row.ai_impressions, row.clicks] })
      .to eq([["/post/cited", 40, 1], ["/post/clicked", 20, 15]])
  end

  it "lists pages search shows often that no AI answer did" do
    ai_page("/post/cited", 40)
    search_page("/post/cited", clicks: 1, impressions: 90)
    search_page("/post/missing", clicks: 3, impressions: 70)
    search_page("/post/rare", clicks: 0, impressions: 5)

    expect(gaps.missing_from_ai.map { |row| [row.page_path, row.impressions] }).to eq([["/post/missing", 70]])
  end
end
