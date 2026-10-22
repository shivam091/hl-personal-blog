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

  it "ranks entries best overall, keeping the order in the period links" do
    get leaderboard_report_path

    expect(response).to have_http_status(:ok)
    rows = page.css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.first(4) }
    expect(rows).to eq([["1", "A Post · 1 Jan, 2026", "57%", "50"], ["2", "B Post · 1 Jan, 2026", "43%", "5"]])

    get leaderboard_report_path(sort: "potential")

    expect(page.at_css("nav[aria-label=Order] a[aria-current=true]").text).to eq("Most potential")
    expect(page.at_css("nav[aria-label=Period] a[href*='from=']")["href"]).to include("sort=potential")
  end
end
