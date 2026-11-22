# encoding: UTF-8

require "rails_helper"

RSpec.describe "Consent page gaps", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  it "says so until GA has synced" do
    get consent_page_gap_report_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("GA hasn&#39;t synced yet")
  end

  context "with views on both sides" do
    before do
      %w[/a /b /c /d /e].each do |slug|
        PageView.collection.insert_one("_id" => slug, "slug" => slug, "countriesByDay" => {"2026-10-10" => {"IN" => 100}})
        Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: slug, views: 80)
      end
      PageView.collection.insert_one("_id" => "/broken", "slug" => "/broken", "countriesByDay" => {"2026-10-10" => {"IN" => 100}})
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/broken/", views: 10)
    end

    it "lists each page with its gap and flags the page losing most" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      page = Nokogiri::HTML5(response.body)
      row = page.css("#page-gap-table tbody tr").find { |tr| tr.text.include?("/broken") }
      expect(row.text.squish).to include("100", "10", "90", "90.0%", "Well above the median")
      expect(page.text.squish).to include("The median page loses 20.0% of its views to GA.", "1 page flagged")
    end

    it "sits under the consent report in the breadcrumb" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      crumbs = Nokogiri::HTML5(response.body).css("nav[aria-label='Breadcrumb'] li").map { |item| item.text.squish }
      expect(crumbs).to eq(["Dashboard", "Reports", "Consent", "Page gaps"])
    end

    it "keeps a long address from widening the table" do
      long = "/unsubscribe/#{"a" * 120}"
      PageView.collection.insert_one("_id" => long, "slug" => long, "countriesByDay" => {"2026-10-10" => {"IN" => 3}})

      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      link = Nokogiri::HTML5(response.body).css("#page-gap-table a").find { |anchor| anchor.text == long }
      expect(link["title"]).to eq(long)
      expect(link["class"]).to include("truncate")
    end

    it "words a median GA counts more on as GA's extra" do
      Google::Analytics::Stat.where(:page_path.in => %w[/a /b /c /d /e]).update_all(views: 125)

      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      text = Nokogiri::HTML5(response.body).text.squish
      expect(text).to include("GA counts 25.0% more views than we do on the median page.")
      expect(text).not_to include("loses -")
    end

    it "plots each judged page against its views, amber when flagged, linking to its statistics" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      dots = Nokogiri::HTML5(response.body).css("section[aria-labelledby='gap-against-views'] span[data-tip]")
      tips = dots.to_h { |dot| [JSON.parse(dot["data-tip"])["title"], [dot["style"], JSON.parse(dot["data-tip"])]] }
      expect(tips.keys).to contain_exactly("/a", "/b", "/c", "/d", "/e", "/broken")
      style, tip = tips["/broken"]
      expect(style).to include(PageGapsHelper::FLAGGED_COLOR)
      expect(tip["href"]).to eq(page_view_path("/broken", from: "2026-10-10", to: "2026-10-12"))
      expect(tip["rows"].map { |row| row["value"] }).to eq(["100", "10", "90.0%"])
    end

    it "ranks the pages by views missing, each with its share of them all" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      rows = Nokogiri::HTML5(response.body).css("section[aria-labelledby='missing-views'] li [data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
      expect(rows.first["title"]).to eq("/broken")
      expect(rows.first["rows"].map { |row| row["value"] }).to eq(["90", "47.37%"])
      expect(rows.size).to eq(6)
    end

    it "sets our views against GA's for each flagged page" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      rows = Nokogiri::HTML5(response.body).css("section[aria-labelledby='flagged-views'] li[data-tip]")
      expect(rows.map { |row| row.at_css("a").text }).to eq(["/broken"])
      expect(JSON.parse(rows.first["data-tip"])["rows"].map { |row| row["value"] }).to eq(["100", "10", "90"])
    end

    it "breaks each flagged page's gap into causes, or says it can't" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")
      expect(Nokogiri::HTML5(response.body).at_css("section[aria-labelledby='flagged-causes']").text).to include("No days with the consent split")

      PageView.collection.update_one({"_id" => "/broken"}, {"$set" => {"consentByDay" => {"2026-10-10" => {"granted" => 50, "denied" => 50}}}})
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12")

      bar = Nokogiri::HTML5(response.body).at_css("section[aria-labelledby='flagged-causes'] [data-tip]")
      readings = JSON.parse(bar["data-tip"])["rows"].to_h { |row| [row["name"], row["value"]] }
      expect(readings).to include("Declined" => "50 · 55.56%", "Unexplained" => "40 · 44.44%")
    end

    it "sorts by a column asked for" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12", sort: "gap", direction: "asc")

      slugs = Nokogiri::HTML5(response.body).css("#page-gap-table tbody tr td:first-child").map { |cell| cell.text.strip }
      expect(slugs.last).to eq("/broken")
    end

    it "exports the table as CSV" do
      get consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12", format: :csv)

      expect(response.media_type).to eq("text/csv")
      expect(CSV.parse(response.body, headers: true).map { |row| row["Page"] }).to include("/broken")
    end
  end
end
