# encoding: UTF-8

require "rails_helper"

RSpec.describe "Month and year review", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a",
      "countriesByDay" => {"2026-09-10" => {"IN" => 30}, "2026-08-10" => {"IN" => 10}})
  end

  it "opens on the month just ended, set against the month before" do
    get review_report_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to eq("Review of September 2026")
    expect(page.at_css("nav[aria-label='Review span'] a[aria-current=true]").text).to eq("September 2026")
    views = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Views") }
    expect(views.css("dd").map { |dd| dd.text.squish }).to eq(["30", "200.0%"])
    expect(views.at_css("[role=tooltip]").text.squish).to eq("Human page views in the span; bots are counted apart and left out.")
    expect(page.css("dl > div [role=tooltip]").size).to eq(8)
    expect(page.css("#review-top-pages ~ ol li").map { |row| row.text.squish }).to eq(["/post/a 30"])
  end

  it "reviews a year when one is picked" do
    get review_report_path(span: "2025")

    expect(page.at_css("h1").text).to eq("Review of 2025")
    expect(page.at_css("#review-top-pages ~ p").text).to eq("No views in this span.")
    expect(page.text).to include("Page views are counted from 10 Aug, 2026, so earlier days in this period have none.")
  end
end
