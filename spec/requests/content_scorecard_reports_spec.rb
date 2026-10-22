# encoding: UTF-8

require "rails_helper"

RSpec.describe "Content scorecard", type: :request do
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
    get content_scorecard_report_path
    expect(page.css("thead th").map { |th| th.text.squish }).not_to include("AI impressions")

    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 9, 1), impressions: 9)
    Google::SearchConsole::GenerativeAiRow.create!(search_type: "Web", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30),
      breakdown: "pages", label: "https://blog.example.com/post/b", impressions: 9)
    get content_scorecard_report_path

    expect(page.css("thead th").last.text.squish).to eq("AI impressions")
    expect(page.css("tbody tr").map { |row| [row.css("td")[1].text.squish.first(6), row.css("td").last.text.squish] })
      .to eq([["A Post", "0"], ["B Post", "9"]])

    get content_scorecard_report_path(format: :csv)
    csv = CSV.parse(response.body, headers: true)
    expect(csv.map { |row| [row["Title"], row["AI impressions 2026-09-01 to 2026-09-30"]] }).to eq([["A", "0"], ["B", "9"]])
  end

  it "sets each entry's views against the period before, and leaves the changes out with the comparison off" do
    PageView.collection.update_one({"_id" => "/post/a"}, {"$set" => {"countriesByDay.2026-09-01" => {"IN" => 25}}})

    get content_scorecard_report_path

    expect(page.at_css("#period-compare")).to be_present
    expect(page.css("tbody tr").first.css("td")[3].text).to include("(+100%)")
    get content_scorecard_report_path(format: :csv)
    expect(CSV.parse(response.body, headers: true).first["Views"]).to eq("50 (+100%)")

    get content_scorecard_report_path(compare: "off")

    expect(page.css("tbody tr").first.css("td")[3].text).not_to include("(")
  end

  it "ranks entries best overall, keeping the order in the period links" do
    get content_scorecard_report_path

    expect(response).to have_http_status(:ok)
    rows = page.css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.first(4) }
    expect(rows).to eq([["1", "A Post · 1 Jan, 2026", "57%", "50"], ["2", "B Post · 1 Jan, 2026", "43%", "5"]])

    get content_scorecard_report_path(sort: "potential")

    expect(page.at_css("nav[aria-label=Order] a[aria-current=true]").text).to eq("Most potential")
    expect(page.at_css("nav[aria-label=Period] a[href*='from=']")["href"]).to include("sort=potential")
  end

  it "exports the entries in the chosen order as CSV" do
    get content_scorecard_report_path(format: :csv, sort: "potential")

    rows = CSV.parse(response.body)
    expect(rows.first.first(8)).to eq(["URL", "Title", "Type", "Published", "Score", "Potential", "Views", "Views rank"])
    expect(rows.drop(1).map { |row| row.values_at(0, 6) }).to match_array([["https://blog.example.com/post/a", "50"], ["https://blog.example.com/post/b", "5"]])
    expect(ExportRequest.first.detail).to include("Most potential")
  end

  it "offers the compare menu beside the country filter" do
    get content_scorecard_report_path

    expect(page.at_css("[aria-controls=period-compare]")).to be_present
    expect(page.at_css("[aria-controls=period-country]")).to be_present
  end

  describe "consent figures" do
    def tile(label)
      page.css("#consent-kpis > div").find { |tile| tile.at_css("dt").text.include?(label) }.css("dd").map { |dd| dd.text.squish }
    end

    it "shows GA's share of our views and the banner's acceptance, each against the period before" do
      ConsentSnapshot.create!(day: "2026-10-10", first_party: 100, analytics: 60)
      ConsentSnapshot.create!(day: "2026-09-10", first_party: 100, analytics: 80)
      ConsentChoice.collection.insert_many([
        {"_id" => "2026-10-10", "day" => "2026-10-10", "countries" => {"DE" => {"shown" => 20, "granted" => 6, "denied" => 4}, "FR" => {"granted" => 3, "denied" => 1}}},
        {"_id" => "2026-09-10", "day" => "2026-09-10", "countries" => {"DE" => {"shown" => 20, "granted" => 5, "denied" => 5}}}
      ])

      get content_scorecard_report_path

      expect(tile("GA's share of our views")).to eq(["60.0%", "25.0%"])
      expect(page.at_css("#consent-kpis").css("dd span[title]").map { |span| span["title"] }).to eq(["Down from 80.0% in the period before", "Up from 50.0% in the period before"])
      expect(tile("Banner acceptance")).to eq(["64.3%", "28.6%"])
    end

    it "shows a dash with too few views or answers to judge" do
      ConsentSnapshot.create!(day: "2026-10-10", first_party: 10, analytics: 6)
      ConsentChoice.collection.insert_one("_id" => "2026-10-10", "day" => "2026-10-10", "countries" => {"DE" => {"shown" => 4, "granted" => 2, "denied" => 1}})

      get content_scorecard_report_path(compare: "off")

      expect(tile("GA's share of our views")).to eq(["—"])
      expect(tile("Banner acceptance")).to eq(["—"])
    end
  end
end
