# encoding: UTF-8

require "rails_helper"

RSpec.describe "Consent report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def card(id)
    Nokogiri::HTML5(response.body).css("section[aria-labelledby=#{id}]").text.squish
  end

  it "says so when nothing has been recorded" do
    get consent_report_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No consent answers or consent-split views recorded")
  end

  context "with consent recorded" do
    before do
      ConsentChoice.collection.insert_one("_id" => "2026-10-10", "day" => "2026-10-10", "countries" => {"GB" => {"shown" => 10, "granted" => 3, "denied" => 5}})
      PageView.collection.insert_one(
        "_id" => "/post/a", "slug" => "/post/a",
        "countriesByDay" => {"2026-10-10" => {"GB" => 100}},
        "consentByDay" => {"2026-10-10" => {"granted" => 20, "denied" => 30, "unset" => 50}}
      )
    end

    it "shows the funnel and the views by consent state" do
      get consent_report_path

      expect(card("banner-by-country")).to include("GB", "10", "37.5%")
      expect(card("views-by-consent")).to include("Declined", "30", "30.0%")
      expect(response.body).not_to include("Explained by declines")
    end

    it "sets our views against GA's once GA has synced, and explains the gap" do
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/a", views: 60)

      get consent_report_path

      page = Nokogiri::HTML5(response.body)
      expect(page.text.squish).to include("Explained by declines")
      expect(card("views-against-ga")).to include("Oct", "100", "60", "40", "30")
    end

    it "exports the funnel as CSV" do
      get consent_report_path(format: :csv)

      expect(response.media_type).to eq("text/csv")
      expect(CSV.parse(response.body, headers: true).map { |row| row["Country"] }).to eq(%w[GB All])
    end
  end

  context "with the gap tracking fields recorded" do
    before do
      ConsentChoice.collection.insert_one("_id" => "2026-10-10", "day" => "2026-10-10", "countries" => {"GB" => {"shown" => 40, "granted" => 10, "denied" => 20}})
      PageView.collection.insert_one(
        "_id" => "/post/a", "slug" => "/post/a",
        "countriesByDay" => {"2026-10-10" => {"GB" => 90, "UNKNOWN" => 10}},
        "consentByDay" => {"2026-10-10" => {"granted" => 20, "denied" => 30, "pending" => 30, "default" => 20}},
        "gaByDay" => {"2026-10-10" => {"loaded" => 85, "blocked" => 10}},
        "suspectByDay" => {"2026-10-10" => {"datacentre" => 5}}
      )
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/a", views: 30)
    end

    it "puts the gap down to its causes and shows what is left" do
      get consent_report_path(from: "2026-10-10", to: "2026-10-12")

      expect(card("gap-causes")).to include("Declined the banner", "30", "Not yet answered the banner", "Ad or tracker blocker", "Unexplained")
      expect(card("unexplained-by-day")).to include("Oct", "70")
    end

    it "charts the gap's causes by day while the period is too short for weeks, leaving out days it can't explain" do
      get consent_report_path(from: "2026-10-10", to: "2026-10-12")

      expect(card("gap-causes-over-time")).to include("Declined", "Datacentre", "Unexplained", "2 days without GA's figures or the consent split are left out")
      expect(Nokogiri::HTML5(response.body).at_css("select#causes-by")).to be_nil
    end

    it "charts the causes by week by default once the period allows, and by day when asked" do
      get consent_report_path(from: "2026-09-20", to: "2026-10-12")

      expect(Nokogiri::HTML5(response.body).at_css("select#causes-by option[selected]")["value"]).to eq("week")

      get consent_report_path(from: "2026-09-20", to: "2026-10-12", by: "day")

      expect(Nokogiri::HTML5(response.body).at_css("select#causes-by option[selected]")["value"]).to eq("day")
    end

    it "says so when the causes found add up to more than the gap" do
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 10), page_path: "/post/b", views: 65)

      get consent_report_path(from: "2026-10-10", to: "2026-10-12")

      expect(card("gap-causes-over-time")).to include("the causes found add up to more than the gap, so Unexplained is below zero")
    end

    it "splits views by the finer states" do
      get consent_report_path(from: "2026-10-10", to: "2026-10-12")

      expect(card("views-by-consent")).to include("Banner due, not yet answered", "No banner needed")
    end

    it "shows the banner's health and the views no country was known for" do
      get consent_report_path(from: "2026-10-10", to: "2026-10-12")

      expect(card("banner-health")).to include("Banners shown", "40", "Such views per banner", "10.0%")
    end

    it "links to the page gaps" do
      get consent_report_path(from: "2026-10-10", to: "2026-10-12")

      hrefs = Nokogiri::HTML5(response.body).css("a").map { |link| link["href"] }
      expect(hrefs).to include(consent_page_gap_report_path(from: "2026-10-10", to: "2026-10-12"))
    end
  end
end
