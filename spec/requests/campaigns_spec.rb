# encoding: UTF-8

require "rails_helper"

RSpec.describe "Campaigns and referrer notes", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-12-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a", "url" => "https://blog.example.com/post/a", "createdAt" => Time.utc(2026, 12, 1),
      "countriesByDay" => {"2026-12-05" => {"IN" => 4}},
      "campaignsByDay" => {"2026-12-05" => {"newsletter|email|new_entry|title|tutorial|tutorials-grid" => 3, "reddit|social|(none)" => 1}})
  end

  it "lists a page's campaigns in the period by source, medium, name, content, term and id" do
    get page_view_path("/post/a")

    rows = page.css("#period-campaigns ~ div tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
    expect(rows).to eq([["newsletter", "email", "new_entry", "title", "tutorial", "tutorials-grid", "3", "75.0%"],
      ["reddit", "social", "(none)", "(none)", "(none)", "(none)", "1", "25.0%"]])
  end

  it "shows every page's campaigns on the dashboard" do
    get root_path

    expect(page.at_css("#campaigns").parent.text).to include("newsletter", "new_entry")
  end
end
