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
