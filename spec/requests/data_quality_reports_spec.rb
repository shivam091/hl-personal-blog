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

  it "adds a strip for each consent tally, telling the days before it began from those it missed" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {
      "consentByDay" => {"2026-10-08" => {"granted" => 3}, "2026-10-10" => {"denied" => 1}},
      "gaByDay" => {"2026-10-10" => {"loaded" => 3}}, "suspectByDay" => {"2026-10-10" => {"datacentre" => 1}}
    }})

    get data_quality_report_path(from: "2026-10-06", to: "2026-10-11")

    strips = page.css("#coverage ~ div > div").to_h { |strip| [strip.at_css("p span").text.squish, strip] }
    expect(strips.keys).to eq(["Blog views", "Search Console", "Google Analytics", "reCAPTCHA",
      "Consent split from 8 Oct", "Tag loading from 10 Oct", "Automation from 10 Oct"])
    tips = ->(name) { strips.fetch(name).css("[data-tip]").map { JSON.parse(it["data-tip"])["rows"].first["value"] } }
    expect(strips["Consent split from 8 Oct"].text).to include("2 days missing")
    expect(tips.("Consent split from 8 Oct")).to eq(["Not recorded yet", "Not recorded yet", "Has data", "Missing", "Has data", "Missing"])
    expect(strips["Tag loading from 10 Oct"].text).to include("1 day missing")
    expect(strips["Automation from 10 Oct"].text).to include("Every day")
    expect(tips.("Automation from 10 Oct").last(2)).to eq(["Has data", "Nothing flagged"])
  end

  it "says a tally wasn't recorded in the period compared with, rather than that it had every day" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {"consentByDay" => {"2026-10-10" => {"granted" => 3}}, "countriesByDay.2026-10-08" => {"IN" => 5}}})
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 8), page_path: "/post/a", views: 4)

    get data_quality_report_path(from: "2026-10-10", to: "2026-10-11")

    strip = page.css("#coverage ~ div > div").find { it.at_css("p span").text.squish == "Consent split" }
    expect(strip.at_css("p").text.squish).to end_with("1 day missing (new)")
    tag_loading = page.css("#coverage ~ div > div").find { it.at_css("p span").text.squish == "Tag loading" }
    expect(tag_loading.at_css("p").text.squish).to eq("Tag loading Not recorded yet (new)")
  end

  it "marks the pages Page gaps flags and links to it for the same period" do
    %w[/post/b /post/c /post/d /post/broken].each do |slug|
      PageView.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => {"2026-10-10" => {"IN" => 100}})
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "#{slug}/", views: slug == "/post/broken" ? 20 : 75)
    end

    get data_quality_report_path(from: "2026-10-01", to: "2026-10-11")

    rows = page.css("#page-comparison ~ div tbody tr").to_h { |row| [row.at_css("td a").text.strip, row.at_css("td")] }
    marked = rows.select { |_, cell| cell.at_css("[title^='Page gaps flags']") }
    expect(marked.keys).to eq(["/post/broken"])
    expect(marked["/post/broken"].at_css("[title^='Page gaps flags']")["title"]).to eq(
      "Page gaps flags this page: GA misses 80% of its views, against a median of 25% across pages."
    )
    link = page.css("#page-comparison ~ p a").find { it.text.squish == "Page gaps" }
    expect(link["href"]).to eq(consent_page_gap_report_path(from: "2026-10-01", to: "2026-10-11"))
  end

  it "sets each page's counts against the period before, and leaves the changes out with the comparison off" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {"countriesByDay.2026-09-01" => {"IN" => 20}}})
    Google::Analytics::Stat.create!(date: Date.new(2026, 9, 1), page_path: "/post/a", views: 15)

    get data_quality_report_path

    expect(page.at_css("#period-compare")).to be_present
    expect(page.css("#page-comparison ~ div tbody tr:first-child td").map { it.text.squish }.first(3)).to eq(["/post/a", "40 (+100%)", "30 (+100%)"])

    expect(page.css("#page-comparison ~ div tbody tr:first-child td").last.text.squish).to eq("−25% was −25%")

    get data_quality_report_path(compare: "off")

    expect(page.css("#page-comparison ~ div tbody tr:first-child td").map { it.text.strip }).to eq(%w[/post/a 40 30 −25%])
  end

  it "adds the earlier difference to the export once there is a period before" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {"countriesByDay.2026-09-01" => {"IN" => 20}}})
    Google::Analytics::Stat.create!(date: Date.new(2026, 9, 1), page_path: "/post/a", views: 15)

    get data_quality_report_path(format: :csv)

    expect(CSV.parse(response.body)).to eq([[*ViewComparison::CSV_HEADERS, "Difference before"], ["/post/a", "40 (+100%)", "30 (+100%)", "-0.25", "-0.25"]])
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

  it "keeps the country filter beside the comparison" do
    get data_quality_report_path

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("[aria-controls=period-compare]")).to be_present
    expect(page.at_css("[aria-controls=period-country]")).to be_present
  end
end
