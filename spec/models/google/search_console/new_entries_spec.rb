# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::NewEntries do
  def entry(path, published:)
    FeedEntry.create!(
      url: "https://blog.example.com#{path}",
      name: path,
      type: "snippet",
      published_at: published,
      last_modified_at: published
    )
  end

  def page(path, **attributes)
    CrawledPage.create!(url: "https://blog.example.com#{path}", last_modified_at: 1.day.ago, **attributes)
  end

  it "lists recent entries Google hasn't indexed, newest first, with where each is stuck" do
    entry("/snippet/unlisted", published: 1.day.ago)
    entry("/snippet/waiting", published: 3.days.ago)
    entry("/snippet/excluded", published: 5.days.ago)
    entry("/snippet/indexed", published: 2.days.ago)
    entry("/snippet/old", published: 40.days.ago)
    page("/snippet/waiting")
    Google::SearchConsole::UrlInspection.create!(
      crawled_page: page("/snippet/excluded"),
      verdict: "NEUTRAL",
      coverage_state: "Discovered - currently not indexed",
      inspected_at: 1.day.ago
    )
    page("/snippet/indexed", indexed: true)
    page("/snippet/old")

    rows = described_class.new.not_indexed

    expect(rows.map { |row| [row.entry.url.delete_prefix("https://blog.example.com"), row.status] }).to eq([
      ["/snippet/unlisted", "Not in the sitemap, so not inspected"],
      ["/snippet/waiting", "Not inspected yet"],
      ["/snippet/excluded", "Discovered - currently not indexed"]
    ])
  end
end
