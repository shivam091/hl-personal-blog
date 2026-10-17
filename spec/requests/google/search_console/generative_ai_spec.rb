# encoding: UTF-8

require "rails_helper"

RSpec.describe "Search Console generative AI performance", type: :request do
  around { |example| travel_to(Time.zone.local(2026, 10, 12, 9)) { example.run } }

  let(:stats) { Google::SearchConsole::GenerativeAiStat }

  it "explains how to get figures in before any upload" do
    get google_search_console_generative_ai_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Export › Download Excel")
    expect(Nokogiri::HTML5(response.body).css("input[type=file][name=file]")).not_to be_empty
  end

  it "keeps an upload's days and breakdowns, and shows them for the period" do
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload}

    expect(response).to redirect_to(google_search_console_generative_ai_path)
    expect(flash[:notice]).to include("Web (text-based)", "2 new days", "0 days updated")
    expect(stats.order(date: :asc).pluck(:date, :impressions)).to eq([[Date.new(2026, 10, 1), 3], [Date.new(2026, 10, 2), 5]])
    devices = Google::SearchConsole::GenerativeAiRow.where(breakdown: "devices")
    expect(devices.pluck(:search_type, :from, :to).uniq).to eq([["Web (text-based)", Date.new(2026, 10, 1), Date.new(2026, 10, 2)]])
    expect(devices.pluck(:label, :impressions)).to contain_exactly(["Desktop", 7], ["Mobile", 1])

    get google_search_console_generative_ai_path(from: "2026-10-01", to: "2026-10-11")

    page = Nokogiri::HTML5(response.body)
    expect(page.css("dl dd").first.text.squish).to eq("8")
    expect(page.css("section[aria-labelledby=generative-ai-impressions] [data-tip]")).not_to be_empty
    expect(table_rows).to eq([["1", "/post/grid", "6", "60.0%"], ["2", "/", "4", "40.0%"]])
    expect(page.css("thead tr:last-child").text.squish).to include("Total 10 100%")
    expect(response.body).to include("whatever period is picked")

    get google_search_console_generative_ai_breakdown_path("countries", sort: "country", direction: "desc")
    expect(table_rows.map(&:second)).to eq(["🇺🇸 US", "🇮🇳 IN"])
    expect(Nokogiri::HTML5(response.body).css("tbody td span[title]").map { |cell| cell["title"] }).to eq(["United States", "India"])
    map = Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=generative-ai-countries]")
    expect(map.css("svg path[data-tip]").map { |path| JSON.parse(path["data-tip"]) }.find { |tip| tip["title"].include?("India") }["rows"].first["value"]).to eq("6")

    get google_search_console_generative_ai_breakdown_path("pages")
    expect(Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=generative-ai-countries]")).to be_nil
  end

  it "lists the period's days on the Dates tab, each against the same day of the period compared with" do
    stats.create!(search_type: "Web", date: Date.new(2026, 9, 28), impressions: 10)
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 5), impressions: 15)
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 6), impressions: 5)

    get google_search_console_generative_ai_breakdown_path("dates", from: "2026-10-05", to: "2026-10-11")

    expect(table_rows.map { |row| row.first(3) }).to eq([["1", I18n.l(Date.new(2026, 10, 6)), "5 (new)"], ["2", I18n.l(Date.new(2026, 10, 5)), "15 (+50%)"]])
    expect(response.body).not_to include("whatever period is picked")
  end

  it "shows a country Google names some unknown way by its name, rather than dropping it" do
    tabs = GenerativeAiExport::DEFAULT_TABS.merge("Countries" => [["Country", "Impressions"], ["Türkiye", 3], ["Atlantis", 1]])
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload(tabs)}

    get google_search_console_generative_ai_breakdown_path("countries")
    expect(table_rows.map(&:second)).to eq(["🇹🇷 TR", "Atlantis"])
  end

  def table_rows
    Nokogiri::HTML5(response.body).css("table tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
  end

  def section(id)
    Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=#{id}]")
  end

  # The upload names its type as Google labels it ("Web (text-based)"), while
  # synced search figures are keyed by the API's "web".
  it "charts AI impressions as a share of the synced search impressions, whatever Google calls the upload's type" do
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload}
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 1), impressions: 30)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 2), impressions: 50)

    get google_search_console_generative_ai_path(from: "2026-10-01", to: "2026-10-11")

    expect(section("generative-ai-share")).not_to be_nil
  end

  it "sets each page and country beside its search impressions over the upload's days" do
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload}
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 1), page: "https://example.com/post/grid", page_path: "/post/grid", impressions: 40)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 2), page: "https://example.com/post/grid", page_path: "/post/grid", impressions: 20)
    Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 5), page: "https://example.com/post/grid", page_path: "/post/grid", impressions: 500)
    Google::SearchConsole::CountryStat.create!(date: Date.new(2026, 10, 1), country: "IN", impressions: 24)

    get google_search_console_generative_ai_breakdown_path("pages")

    expect(table_rows).to eq([["1", "/post/grid", "6", "60.0%", "60", "10.0%"], ["2", "/", "4", "40.0%", "—", "—"]])
    expect(Nokogiri::HTML5(response.body).css("thead tr:last-child").text.squish).to include("Total 10 100% 60 16.7%")

    get google_search_console_generative_ai_breakdown_path("countries")

    expect(table_rows.map { |row| row.drop(1) }).to eq([["🇮🇳 IN", "6", "75.0%", "24", "25.0%"], ["🇺🇸 US", "2", "25.0%", "—", "—"]])
  end

  it "counts visits from AI assistants, from GA, whether or not anything was uploaded" do
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 5), page_path: "/post/grid", views: 9)
    Google::Analytics::LandingSourceStat.create!(date: Date.new(2026, 10, 5), page_path: "/post/grid", channel_group: "Referral",
      source: "chatgpt.com", medium: "referral", sessions: 3, engaged_sessions: 3)
    Google::Analytics::LandingSourceStat.create!(date: Date.new(2026, 10, 5), page_path: "/post/grid", channel_group: "Organic Search",
      source: "google", medium: "organic", sessions: 40)

    get google_search_console_generative_ai_path(from: "2026-10-01", to: "2026-10-11")

    expect(section("ai-assistant-visits").at_css("#ai-assistant-totals").text.squish).to start_with("3 visits")
    expect(section("ai-assistant-visits").text).to include("ChatGPT")

    post google_search_console_generative_ai_path, params: {file: generative_ai_upload}
    get google_search_console_generative_ai_path(from: "2026-10-01", to: "2026-10-11")

    expect(section("ai-assistant-visits").at_css("#ai-assistant-totals").text.squish).to start_with("3 visits")
  end

  it "says when an upload leaves days uncovered beside those already kept" do
    stats.create!(search_type: "Web (text-based)", date: Date.new(2026, 9, 20), impressions: 1)

    post google_search_console_generative_ai_path, params: {file: generative_ai_upload}

    expect(flash[:notice]).to include("No upload covers #{I18n.l(Date.new(2026, 9, 21))} – #{I18n.l(Date.new(2026, 9, 30))}")

    later = GenerativeAiExport::DEFAULT_TABS.merge("Chart" => [["Date", "Impressions"], ["2026-10-03", 2]])
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload(later)}

    expect(flash[:notice]).not_to include("No upload covers")
  end

  it "replaces days a later upload covers again, leaving the rest, and shows the latest upload's breakdowns" do
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload}
    later = GenerativeAiExport::DEFAULT_TABS.merge(
      "Chart" => [["Date", "Impressions"], ["2026-10-02", 9], ["2026-10-03", 4]],
      "Countries" => [["Country", "Impressions"], ["Brazil", 13]]
    )
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload(later, filename: "later.xlsx")}

    expect(flash[:notice]).to include("1 new day", "1 day updated")
    expect(stats.order(date: :asc).pluck(:impressions)).to eq([3, 9, 4])

    get google_search_console_generative_ai_breakdown_path("countries")
    expect(table_rows.map(&:second)).to eq(["🇧🇷 BR"])
    expect(Google::SearchConsole::GenerativeAiRow.where(breakdown: "countries").pluck(:label)).to eq(["Brazil"])
    expect(response.body).to include("cover #{I18n.l(Date.new(2026, 10, 2))} – #{I18n.l(Date.new(2026, 10, 3))}")
  end

  it "compares with the period before once there are days from before it" do
    stats.create!(search_type: "Web", date: Date.new(2026, 9, 5), impressions: 10)
    stats.create!(search_type: "Web", date: Date.new(2026, 10, 5), impressions: 15)

    get google_search_console_generative_ai_path(from: "2026-10-05", to: "2026-10-11")

    expect(Nokogiri::HTML5(response.body).css("dl dd")[1].text.squish).to include("No earlier data")

    get google_search_console_generative_ai_path(from: "2026-10-05", to: "2026-10-11", compare: "month")

    expect(Nokogiri::HTML5(response.body).css("dl dd")[1].text.squish).to include("50")
  end

  it "keeps search types apart, offering a choice once there's more than one" do
    stats.create!(search_type: "Web (text-based)", date: Date.new(2026, 10, 5), impressions: 15)
    stats.create!(search_type: "Web (text-based)", date: Date.new(2026, 10, 6), impressions: 5)
    stats.create!(search_type: "Web (multimodal)", date: Date.new(2026, 10, 5), impressions: 2)

    get google_search_console_generative_ai_path
    page = Nokogiri::HTML5(response.body)
    expect(page.css("nav[aria-label='Search type'] a").map(&:text)).to eq(["Web (text-based)", "Web (multimodal)"])
    expect(page.css("dl dd").first.text.squish).to eq("20")

    get google_search_console_generative_ai_path(type: "Web (multimodal)")
    expect(Nokogiri::HTML5(response.body).css("dl dd").first.text.squish).to eq("2")
  end

  it "keeps nothing from a file that isn't the export, and says why" do
    post google_search_console_generative_ai_path, params: {file: generative_ai_upload(GenerativeAiExport::DEFAULT_TABS.except("Devices"))}

    expect(response).to redirect_to(google_search_console_generative_ai_path)
    expect(flash[:alert]).to include("no Devices tab")
    expect(stats.count).to eq(0)
    expect(Google::SearchConsole::GenerativeAiRow.count).to eq(0)

    post google_search_console_generative_ai_path
    expect(flash[:alert]).to include("Choose the spreadsheet")
  end

  describe "the link to Search Console's own report" do
    def search_console_link
      Nokogiri::HTML5(response.body).css("a").find { |link| link.text.squish == "Open in Search Console" }
    end

    # So the link doesn't depend on whatever the local credentials hold (CI has none).
    def configure_site(site)
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:google, :search_console_site) { site }
    end

    it "opens the report's Search view for the configured property, in a new tab" do
      configure_site("sc-domain:example.com")
      post google_search_console_generative_ai_path, params: {file: generative_ai_upload}

      get google_search_console_generative_ai_path

      expect(search_console_link["href"])
        .to eq("https://search.google.com/search-console/performance/search-analytics/ai?resource_id=sc-domain%3Aexample.com")
      expect(search_console_link["target"]).to eq("_blank")
    end

    it "opens the Discover view for a Discover upload" do
      configure_site("https://example.com/")
      post google_search_console_generative_ai_path, params: {
        file: generative_ai_upload(GenerativeAiExport::DEFAULT_TABS.merge("Filters" => [["Filter", "Value"], ["Search type", "Discover"]]))
      }

      get google_search_console_generative_ai_path(type: "Discover")

      expect(search_console_link["href"])
        .to eq("https://search.google.com/search-console/performance/discover/ai?resource_id=https%3A%2F%2Fexample.com%2F")
    end

    it "isn't shown until a property is configured" do
      configure_site(nil)

      get google_search_console_generative_ai_path

      expect(search_console_link).to be_nil
    end
  end
end
