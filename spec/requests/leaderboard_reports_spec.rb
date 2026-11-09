# encoding: UTF-8

require "rails_helper"

RSpec.describe "Post leaderboard", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    %w[/post/a /post/b].each do |path|
      FeedEntry.create!(url: "https://blog.example.com#{path}", name: path.delete_prefix("/post/").upcase, type: "post",
        published_at: Time.zone.parse("2026-01-01"), last_modified_at: Time.zone.parse("2026-01-01"))
    end
    PageView.collection.insert_many([
      {"_id" => "/post/a", "slug" => "/post/a", "countriesByDay" => {"2026-10-10" => {"IN" => 50}}},
      {"_id" => "/post/b", "slug" => "/post/b", "countriesByDay" => {"2026-10-10" => {"IN" => 5}}}
    ])
  end

  it "shows each entry's AI impressions from the latest upload beside its measures, without ranking them" do
    get leaderboard_report_path
    expect(page.css("thead th").map { |th| th.text.squish }).not_to include("AI impressions")

    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 9, 1), impressions: 9)
    Google::SearchConsole::GenerativeAiRow.create!(search_type: "Web", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30),
      breakdown: "pages", label: "https://blog.example.com/post/b", impressions: 9)
    get leaderboard_report_path

    expect(page.css("thead th").last.text.squish).to eq("AI impressions")
    expect(page.css("tbody tr").map { |row| [row.css("td")[1].text.squish.first(6), row.css("td").last.text.squish] })
      .to eq([["A Post", "0"], ["B Post", "9"]])

    get leaderboard_report_path(format: :csv)
    csv = CSV.parse(response.body, headers: true)
    expect(csv.map { |row| [row["Title"], row["AI impressions 2026-09-01 to 2026-09-30"]] }).to eq([["A", "0"], ["B", "9"]])
  end

  it "ranks entries best overall, keeping the order in the period links" do
    get leaderboard_report_path

    expect(response).to have_http_status(:ok)
    rows = page.css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.first(4) }
    expect(rows).to eq([["1", "A Post · 1 Jan, 2026", "57%", "50"], ["2", "B Post · 1 Jan, 2026", "43%", "5"]])

    get leaderboard_report_path(sort: "potential")

    expect(page.at_css("nav[aria-label=Order] a[aria-current=true]").text).to eq("Most potential")
    expect(page.at_css("nav[aria-label=Period] a[href*='from=']")["href"]).to include("sort=potential")
  end

  it "exports the entries in the chosen order as CSV" do
    get leaderboard_report_path(format: :csv, sort: "potential")

    rows = CSV.parse(response.body)
    expect(rows.first.first(8)).to eq(["URL", "Title", "Type", "Published", "Score", "Potential", "Views", "Views rank"])
    expect(rows.drop(1).map { |row| row.values_at(0, 6) }).to match_array([["https://blog.example.com/post/a", "50"], ["https://blog.example.com/post/b", "5"]])
    expect(ExportRequest.first.detail).to include("Most potential")
  end

  it "keeps the country filter but leaves comparison off, since nothing on it is compared" do
    get leaderboard_report_path

    expect(page.at_css("[aria-controls=period-compare]")).to be_nil
    expect(page.at_css("[aria-controls=period-country]")).to be_present
  end
end
