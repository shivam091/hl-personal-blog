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
    get month_and_year_review_report_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to eq("Review of September 2026")
    expect(page.at_css("nav[aria-label='Review span'] a[aria-current=true]").text).to eq("September 2026")
    views = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Views") }
    expect(views.css("dd").map { |dd| dd.text.squish }).to eq(["30", "200.0%"])
    expect(views.at_css("[role=tooltip]").text.squish).to eq("Human page views in the span; bots are counted apart and left out.")
    expect(page.css("dl > div [role=tooltip]").size).to eq(9)
    expect(page.css("#review-top-pages ~ ol li").map { |row| row.text.squish }).to eq(["/post/a 30 (+200%)"])
    mover = page.at_css("#review-rising ~ div li[data-tip]")
    expect(mover.at_css("a").text).to eq("/post/a")
    expect(JSON.parse(mover["data-tip"])["rows"].map { |row| [row["name"], row["value"]] }).to eq([["Before", "10"], ["Now", "30"], ["Gap", "20"]])
  end

  it "offers the compare menu, keeping the span, and shows no changes or movers with No comparison" do
    get month_and_year_review_report_path(span: "2026-09", compare: "off")

    expect(page.at_css("[aria-controls=period-compare]").text.squish).to eq("Compare: No comparison")
    expect(page.at_css("#period-compare a[aria-current]").text.squish).to eq("No comparison")
    expect(page.at_css("#period-compare a[href*='compare=week']")["href"]).to include("span=2026-09")
    views = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Views") }
    expect(views.css("dd").map { |dd| dd.text.squish }).to eq(["30"])
    expect(page.css("#review-top-pages ~ ol li").map { |row| row.text.squish }).to eq(["/post/a 30"])
    expect(page.at_css("#review-rising").parent.text).to include("shows once a comparison is picked")
    expect(page.at_css("h1 ~ p").text).not_to include("against")
  end

  it "lets the year so far be set against the period before, which its own default would otherwise replace" do
    get month_and_year_review_report_path(span: "2026")

    expect(page.at_css("#period-compare a[aria-current]").text.squish).to start_with("Same period last year")
    expect(page.at_css("#period-compare a[href*='compare=previous']")["href"]).to include("span=2026")

    get month_and_year_review_report_path(span: "2026", compare: "previous")

    expect(page.at_css("#period-compare a[aria-current]").text.squish).to start_with("Previous period")
    expect(page.at_css("[aria-controls=period-compare]").text.squish).to eq("Compare: vs previous period")
    expect(page.at_css("nav a[href*='span=2026-09']")["href"]).to include("compare=previous")
  end

  it "keeps a month's menu free of an explicit previous period, as its default is already that" do
    get month_and_year_review_report_path(span: "2026-09")

    expect(page.at_css("#period-compare a[href*='compare=previous']")).to be_nil
  end

  it "sets the span against a week back when picked" do
    get month_and_year_review_report_path(span: "2026-09", compare: "week")

    expect(page.at_css("[aria-controls=period-compare]").text.squish).to eq("Compare: vs same period last week")
  end

  it "exports only the span's figures with No comparison" do
    get month_and_year_review_report_path(format: :csv, compare: "off")

    rows = CSV.parse(response.body)
    expect(rows.first).to eq(["Figure", "This span"])
    expect(rows.second).to eq(["Views", "30"])
  end

  it "reviews a year when one is picked" do
    get month_and_year_review_report_path(span: "2025")

    expect(page.at_css("h1").text).to eq("Review of 2025")
    expect(page.at_css("#review-top-pages ~ p").text).to eq("No views in this span.")
    expect(page.text).to include("Page views are counted from 10 Aug, 2026, so earlier days in this period have none.")
  end

  it "exports the span's figures against the one before as CSV" do
    get month_and_year_review_report_path(format: :csv)

    rows = CSV.parse(response.body)
    expect(rows.first).to eq(["Figure", "This span", "Span before", "Change"])
    expect(rows.second).to eq(["Views", "30", "10", "2.0"])
    expect(ExportRequest.first.filename).to eq("month-and-year-review-2026-09.csv")
  end
end
