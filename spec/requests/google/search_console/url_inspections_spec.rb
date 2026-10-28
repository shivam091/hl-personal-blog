# encoding: UTF-8

require "rails_helper"

RSpec.describe "Search Console URL inspections", type: :request do
  let(:indexed_page) { CrawledPage.create!(url: "https://example.com/post/grid", indexed: true, last_modified_at: Time.utc(2026, 7, 5)) }
  let(:excluded_page) { CrawledPage.create!(url: "https://example.com/tag/css", last_modified_at: Time.utc(2026, 7, 5)) }
  let!(:indexed) do
    Google::SearchConsole::UrlInspection.create!(crawled_page: indexed_page, verdict: "PASS", coverage_state: "Submitted and indexed", inspected_at: Time.utc(2026, 10, 10),
      user_canonical: "https://example.com/post/grid", google_canonical: "https://example.com/post/grid",
      inspection_link: "https://search.google.com/search-console/inspect?id=1",
      rich_results_verdict: "PASS", rich_results: [{"type" => "Breadcrumbs", "items" => [{"name" => "Unnamed item", "issues" => []}]}],
      sitemaps: ["https://example.com/sitemap.xml"])
  end
  let!(:excluded) do
    Google::SearchConsole::UrlInspection.create!(crawled_page: excluded_page, verdict: "NEUTRAL", coverage_state: "Alternate page with proper canonical tag", inspected_at: Time.utc(2026, 10, 11),
      user_canonical: "https://example.com/tag/css", google_canonical: "https://example.com/tags")
  end

  it "lists the latest verdicts, newest first, and counts pages never inspected" do
    CrawledPage.create!(url: "https://example.com/new", last_modified_at: Time.utc(2026, 7, 5))

    get google_search_console_url_inspections_path

    page = Nokogiri::HTML5(response.body)
    expect(page.css("tbody tr td:nth-child(2) a:not([target=_blank])").map(&:text)).to eq([excluded_page.url, indexed_page.url])
    expect(page.css("tbody tr").first.text).to include("Excluded", "Google chose a different canonical")
    expect(response.body).to include("1 crawled page not inspected yet.")
  end

  it "charts the pages in each coverage state, coloured by verdict" do
    get google_search_console_url_inspections_path(verdict: "pass")

    bars = Nokogiri::HTML5(response.body).css("#coverage ~ div li[data-tip]")
    expect(bars.map { |bar| JSON.parse(bar["data-tip"])["title"] }).to eq(["Alternate page with proper canonical tag", "Submitted and indexed"])
    expect(bars.map { |bar| bar.at_css("div.h-5")["class"][/bg-\[#\h+\]/] }).to eq(%w[bg-[#a8a7a1] bg-[#1baf7a]])
  end

  it "charts how many days new entries waited for their first crawl" do
    FeedEntry.create!(url: indexed_page.url, name: "Grid", type: "post", published_at: Time.utc(2026, 10, 8), last_modified_at: Time.utc(2026, 10, 8))
    indexed.update!(first_crawled_at: Time.utc(2026, 10, 9, 12), created_at: Time.utc(2026, 10, 9))

    get google_search_console_url_inspections_path

    card = Nokogiri::HTML5(response.body).at_css("#crawl-delays").parent
    expect(card.text).to include("Half were crawled within 1 day.")
    expect(card.css("g[data-tip]").map { |bar| JSON.parse(bar["data-tip"])["rows"].first["value"] }).to eq(%w[0 1 0 0 0 0 0])
  end

  it "lists new entries Google hasn't indexed yet above the verdicts" do
    FeedEntry.create!(
      url: "https://example.com/tag/css",
      name: "CSS tag page",
      type: "post",
      published_at: 2.days.ago,
      last_modified_at: 2.days.ago
    )

    FeedEntry.create!(
      url: "https://example.com/post/unlisted",
      name: "Unlisted post",
      type: "tutorial",
      published_at: 1.day.ago,
      last_modified_at: 1.day.ago
    )

    FeedEntry.create!(
      url: "https://example.com/post/grid",
      name: "Indexed post",
      type: "post",
      published_at: 1.day.ago,
      last_modified_at: 1.day.ago
    )

    get google_search_console_url_inspections_path

    rows = Nokogiri::HTML5(response.body).css("#new-entries ~ div tbody tr").map do |row|
      row.css("td").map { |td| td.text.squish }
    end
    expect(rows.map { |cells| cells.values_at(0, 1, 3) }).to eq([
      ["Unlisted post", "Tutorial", "Not in the sitemap, so not inspected"],
      ["CSS tag page", "Post", "Alternate page with proper canonical tag"]
    ])
  end

  it "searches by the crawled page's URL and filters by verdict" do
    get google_search_console_url_inspections_path(q: "post/")
    expect(response.body).to include(indexed_page.url)
    expect(response.body).not_to include(excluded_page.url)

    get google_search_console_url_inspections_path(verdict: "neutral")
    expect(response.body).to include(excluded_page.url)
    expect(response.body).not_to include(indexed_page.url)
    expect(response.body).to match(%r{Indexed\s*<span[^>]*>1</span>})
  end

  it "finds pages by the issue Google found with them" do
    {"canonical" => [excluded_page], "no_sitemap" => [excluded_page], "no_rich_results" => [excluded_page], "rich_results" => []}.each do |issue, pages|
      get google_search_console_url_inspections_path(issue: issue)

      shown = Nokogiri::HTML5(response.body).css("tbody tr td:nth-child(2) a:not([target=_blank])").map(&:text)
      expect(shown).to eq(pages.map(&:url)), "for #{issue}"
    end

    indexed.update!(rich_results_verdict: "PARTIAL")
    get google_search_console_url_inspections_path(issue: "rich_results", verdict: "pass")
    expect(Nokogiri::HTML5(response.body).css("tbody tr td:nth-child(2) a:not([target=_blank])").map(&:text)).to eq([indexed_page.url])
  end

  it "shows one inspection in full" do
    get google_search_console_url_inspection_path(indexed)

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("h1").text).to eq(indexed_page.url)
    expect(page.at_css("a[href='https://search.google.com/search-console/inspect?id=1']").text).to include("Open in Search Console")
    expect(page.at_css("#rich-results + div").text).to include("Breadcrumbs")
    expect(page.at_css("#found-in").parent.text).to include("https://example.com/sitemap.xml")
  end

  it "times when a page dropped out of the index, on its page and in a list of every such page" do
    Google::SearchConsole::UrlInspectionHistory.create!(crawled_page: excluded_page, url: excluded_page.url, verdict: "PASS",
      coverage_state: "Submitted and indexed", inspected_at: Time.utc(2026, 9, 1))
    Google::SearchConsole::UrlInspectionHistory.create!(crawled_page: excluded_page, url: excluded_page.url, verdict: "NEUTRAL",
      coverage_state: "Alternate page with proper canonical tag", inspected_at: Time.utc(2026, 10, 11))

    get google_search_console_url_inspections_path

    dropped = Nokogiri::HTML5(response.body).css("#dropped ~ div tbody tr")
    expect(dropped.map { |row| row.at_css("td").text.squish }).to eq([excluded_page.url])

    get google_search_console_url_inspection_path(excluded)

    rows = Nokogiri::HTML5(response.body).css("#timeline ~ div tbody tr")
    expect(rows.map { |row| row.css("td")[1].text.squish }).to eq(["Excluded Dropped out of the index", "Indexed"])
  end

  it "exports the filtered inspections" do
    get google_search_console_url_inspections_path(format: :csv, verdict: "pass")

    csv = CSV.parse(response.body, headers: true)
    expect(csv.map { |row| [row["URL"], row["Verdict"]] }).to eq([[indexed_page.url, "PASS"]])
  end

  it "queues the next batch of inspections" do
    expect { post sync_google_search_console_url_inspections_path }.to change(SyncRequest, :count).by(1)
    request = SyncRequest.find_by(kind: "url_inspections")
    expect(request.limit).to eq(100)
    expect(Google::SearchConsole::SyncJob).to have_been_enqueued.with(only: ["url_inspections"], limit: 100, request_id: request.id.to_s)
    expect(flash[:notice]).to start_with("Inspecting the next 100 pages in the background")
  end
end
