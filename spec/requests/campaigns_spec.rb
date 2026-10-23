# encoding: UTF-8

require "rails_helper"

RSpec.describe "Campaigns and referrer notes", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-12-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a",
      "countriesByDay" => {"2026-12-05" => {"IN" => 4}},
      "campaignsByDay" => {"2026-12-05" => {"newsletter|email|new_entry" => 3, "reddit|social|(none)" => 1}})
  end

  it "lists a page's campaigns in the period by source, medium and name" do
    get page_view_path("/post/a")

    rows = page.css("#period-campaigns ~ div tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
    expect(rows).to eq([["newsletter", "email", "new_entry", "3", "75.0%"], ["reddit", "social", "(none)", "1", "25.0%"]])
  end

  it "says referrers before the fix were all internal, only for periods reaching back before it" do
    get page_view_path("/post/a")
    expect(page.at_css("#period-referrers").parent.text).not_to include("counted as Internal")

    get page_view_path("/post/a", from: "2026-10-01", to: "2026-12-11")
    expect(page.at_css("#period-referrers").parent.text).to include("Before 28 Oct, 2026 every view's referrer was counted as Internal")
  end

  it "shows every page's campaigns on the dashboard" do
    get root_path

    expect(page.at_css("#campaigns").parent.text).to include("newsletter", "new_entry")
  end
end
