# encoding: UTF-8

require "rails_helper"

RSpec.describe "Search Console sitemaps", type: :request do
  let!(:clean) do
    Google::SearchConsole::Sitemap.create!(path: "https://example.com/sitemap.xml", sitemap_type: "sitemap",
      last_downloaded_at: Time.utc(2026, 10, 10), contents: [{"type" => "web", "submitted" => 42}])
  end
  let!(:broken) do
    Google::SearchConsole::Sitemap.create!(path: "https://example.com/feed.xml", sitemap_type: "atomFeed",
      last_downloaded_at: Time.utc(2026, 9, 1), error_count: 2, warning_count: 1, pending: true)
  end

  it "lists sitemaps, stalest download first, filterable by errors" do
    get google_search_console_sitemaps_path

    rows = Nokogiri::HTML5(response.body).css("tbody[data-controller=disclosure] > tr:first-child")
    expect(rows.map { |row| row.css("td")[2].text.squish }).to eq(["https://example.com/feed.xml Pending", "https://example.com/sitemap.xml"])
    expect(response.body).to include("Google listed no contents for this sitemap.")

    get google_search_console_sitemaps_path(errors: "no")
    expect(response.body).to include(clean.path)
    expect(response.body).not_to include(broken.path)
    expect(response.body).to match(%r{With errors\s*<span[^>]*>1</span>})
  end

  it "charts every sitemap's URLs and errors over time, and lists each one's changes" do
    [[3, 40, 0], [2, 42, 0], [1, 42, 1]].each do |days, submitted, errors|
      Google::SearchConsole::SitemapHistory.create!(path: clean.path, synced_at: days.days.ago, submitted: submitted, error_count: errors)
    end

    get google_search_console_sitemaps_path

    page = Nokogiri::HTML5(response.body)
    expect(page.css("#sitemap-urls ~ div [data-tip]")).not_to be_empty
    changes = page.css("table[data-sitemap-changes='#{clean.path}'] tbody tr").map { |row| row.css("td")[1..].map { |td| td.text.squish } }
    expect(changes).to eq([["42", "—", "1", "0"], ["42", "—", "0", "0"], ["40", "—", "0", "0"]])
  end

  it "exports the filtered sitemaps" do
    get google_search_console_sitemaps_path(format: :csv, q: "sitemap")

    expect(CSV.parse(response.body)).to eq([
      ["Path", "Type", "Last submitted", "Last downloaded", "Pending", "Sitemap index", "Errors", "Warnings", "Submitted URLs"],
      ["https://example.com/sitemap.xml", "sitemap", nil, "2026-10-10T00:00:00Z", "No", "No", "0", "0", "42"]
    ])
  end

  it "queues a sync of just sitemaps" do
    expect { post sync_google_search_console_sitemaps_path }.to change(SyncRequest, :count).by(1)
    expect(Google::SearchConsole::SyncJob).to have_been_enqueued
      .with(only: ["sitemaps"], request_id: SyncRequest.find_by(kind: "search_console_sitemaps").id.to_s)
    expect(response).to redirect_to(google_search_console_sitemaps_path)
  end

  it "queues a sitemap submission" do
    expect {
      post submit_google_search_console_sitemaps_path
    }.to have_enqueued_job(Google::SearchConsole::SitemapSubmitJob)
    expect(SyncRequest.last.kind).to eq("sitemap_submission")
    expect(response).to redirect_to(google_search_console_sitemaps_path)
  end
end
