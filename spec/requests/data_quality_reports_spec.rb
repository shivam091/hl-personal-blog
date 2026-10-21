# encoding: UTF-8

require "rails_helper"

RSpec.describe "Data quality report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    PageView.collection.insert_one(
      "_id" => "/post/a",
      "slug" => "/post/a",
      "botCount" => 5,
      "visitorCount" => 15,
      "countriesByDay" => {"2026-10-10" => {"IN" => 40}}
    )
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/a", views: 30)
  end

  it "sets the blog's count against GA's, and shows missing days and known gaps" do
    get data_quality_report_path

    expect(response).to have_http_status(:ok)
    expect(page.css("#page-comparison ~ div tbody tr:first-child td").map { it.text.strip }).to eq(%w[/post/a 40 30 −25%])
    expect(page.at_css("#coverage ~ div").text).to include("27 days missing")
    expect(page.at_css("#caveats ~ ul").text.squish).to include("Bots made 5 of 20 hits (25.0%)")
    expect(page.at_css("#data-freshness")).to be_present
    expect(page.css("#bots-by-page ~ div tbody td").map { it.text.strip }).to eq(%w[/post/a 5 15 25.0%])
  end

  it "shows how long pages have waited for indexing and where the feed and sitemap disagree" do
    CrawledPage.create!(url: "https://blog.example.com/post/old", last_modified_at: Time.zone.parse("2026-06-01"))
    FeedEntry.create!(url: "https://blog.example.com/post/new", name: "New post", type: "post",
      published_at: Time.zone.parse("2026-10-10"), last_modified_at: Time.zone.parse("2026-10-10"))

    get data_quality_report_path

    expect(page.css("#index-waiting ~ div tbody td").map { it.text.squish }).to eq(["/post/old", "133"])
    card = page.at_css("#feed-vs-sitemap").parent
    expect(card.text.squish).to include("In the feed, not in the sitemap (1) New post", "Entry pages in the sitemap, not in the feed (1) /post/old")
  end

  it "exports the page comparison" do
    get data_quality_report_path(format: :csv)

    expect(CSV.parse(response.body)).to eq([ViewComparison::CSV_HEADERS, ["/post/a", "40", "30", "-0.25"]])
  end
end
