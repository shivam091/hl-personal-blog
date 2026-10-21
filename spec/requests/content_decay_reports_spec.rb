# encoding: UTF-8

require "rails_helper"

RSpec.describe "Content decay report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    FeedEntry.create!(url: "https://blog.example.com/post/old", name: "Old post", type: "post",
      published_at: Time.zone.parse("2025-01-01"), last_modified_at: Time.zone.parse("2025-01-01"))
    FeedEntry.create!(url: "https://blog.example.com/snippets/tip", name: "Old tip", type: "snippet",
      published_at: Time.zone.parse("2025-01-01"), last_modified_at: Time.zone.parse("2025-01-01"))
    PageView.collection.insert_many([
      {"_id" => "/post/old", "slug" => "/post/old", "countriesByDay" => {"2026-10-05" => {"IN" => 40}}},
      {"_id" => "/snippets/tip", "slug" => "/snippets/tip", "countriesByDay" => {"2026-10-05" => {"IN" => 25}}}
    ])
  end

  it "ranks stale entries still read, with why, saying search losses need a synced period to compare with" do
    get content_decay_report_path

    expect(response).to have_http_status(:ok)
    rows = page.css("tbody tr")
    expect(rows.map { |row| row.css("td")[1].text.squish }).to eq(["Old post Post", "Old tip Snippet"])
    expect(rows.first.css("td")[2].text.squish).to eq("Not updated in 21 months, still read 40 times")
    expect(page.at_css("[role=note]").text.squish).to include("Search Console wasn't synced")
  end

  it "narrows by type" do
    get content_decay_report_path(type: "snippet")

    expect(page.css("tbody tr").map { |row| row.css("td")[1].text.squish }).to eq(["Old tip Snippet"])
  end

  it "exports the queue as CSV" do
    get content_decay_report_path(format: :csv, min_age: "12")

    expect(response.media_type).to eq("text/csv")
    expect(CSV.parse(response.body).drop(1).map { |row| row[1] }).to eq(["https://blog.example.com/post/old", "https://blog.example.com/snippets/tip"])
    expect(ExportRequest.last.detail).to include("Content decay", "Not updated for: 1+ year")
  end
end
