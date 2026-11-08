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
    import = Google::SearchConsole::GenerativeAiImport.last
    expect([import.filename, import.from, import.to]).to eq(["export.xlsx", Date.new(2026, 10, 1), Date.new(2026, 10, 2)])
    expect(import.rows.where(breakdown: "devices").pluck(:label, :impressions)).to contain_exactly(["Desktop", 7], ["Mobile", 1])

    get google_search_console_generative_ai_path(from: "2026-10-01", to: "2026-10-11")

    page = Nokogiri::HTML5(response.body)
    expect(page.css("dl dd").first.text.squish).to eq("8")
    expect(page.css("#generative-ai-impressions ~ div [data-tip]")).not_to be_empty
    expect(table_rows).to eq([["1", "/post/grid", "6", "60.0%"], ["2", "/", "4", "40.0%"]])
    expect(page.css("thead tr:last-child").text.squish).to include("Total 10 100%")
    expect(response.body).to include("Uploaded days run from", "whatever period is picked")

    get google_search_console_generative_ai_breakdown_path("countries", sort: "country", direction: "desc")
    expect(table_rows.map(&:second)).to eq(["🇺🇸 US", "🇮🇳 IN"])
    expect(Nokogiri::HTML5(response.body).css("tbody td span[title]").map { |cell| cell["title"] }).to eq(["United States", "India"])
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
    expect(response.body).to include("later.xlsx")
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
    expect(Google::SearchConsole::GenerativeAiImport.count).to eq(0)

    post google_search_console_generative_ai_path
    expect(flash[:alert]).to include("Choose the spreadsheet")
  end
end
