# encoding: UTF-8

require "rails_helper"

RSpec.describe "PageSpeed", type: :request do
  include ActiveJob::TestHelper

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    Google::PageSpeed::Result.create!(
      url: "https://blog.example.com/post/slow",
      page_path: "/post/slow",
      strategy: "mobile",
      fetched_at: 1.day.ago,
      performance: 0.42,
      accessibility: 1,
      best_practices: 0.96,
      seo: 1,
      field_lcp_ms: 4500,
      field_inp_ms: 150,
      field_cls: 0.05,
      field_source: "page"
    )
    Google::PageSpeed::Result.create!(
      url: "https://blog.example.com/post/fast",
      page_path: "/post/fast",
      strategy: "mobile",
      fetched_at: 1.day.ago,
      performance: 0.98,
      field_source: "origin",
      field_lcp_ms: 2000
    )
    Google::PageSpeed::Result.create!(
      url: "https://blog.example.com/post/fast",
      page_path: "/post/fast",
      strategy: "desktop",
      fetched_at: 1.day.ago,
      performance: 1
    )
  end

  it "lists each test, slowest first, with real users' Core Web Vitals rated" do
    get google_page_speed_results_path(device: "mobile")

    expect(response).to have_http_status(:ok)
    list = page.css("table").last
    rows = list.css("tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }
    expect(rows.map { |cells| cells[1] }).to eq(["/post/slow", "/post/fast"])
    expect(rows.first.values_at(3, 4, 5, 6, 7)).to eq(["42", "100 · 96 · 100", "4.5 s", "150 ms", "0.05"])
    expect(list.css("tbody tr").first.css("td")[5]["class"]).to include("text-red-700")
    expect(rows.second[5]).to eq("2.0 s site")
  end

  it "averages each Lighthouse category by device and grids the weakest pages' scores" do
    get google_page_speed_results_path

    performance = JSON.parse(page.at_css("#category-averages ~ div li[data-tip]")["data-tip"])
    expect([performance["title"], performance["rows"].map { |row| row["value"] }]).to eq(["Performance", ["70", "100", "30"]])
    rows = page.css("#weakest-pages ~ div tbody tr").map { |row| [row.at_css("th").text.strip, *row.css("td").map { |cell| cell.text.strip }] }
    expect(rows).to eq([["/post/slow", "42", "100", "96", "100"], ["/post/fast", "98", "—", "—", "—"]])
  end

  it "charts pages tested on both devices, widest gap first" do
    Google::PageSpeed::Result.create!(
      url: "https://blog.example.com/post/slow",
      page_path: "/post/slow",
      strategy: "desktop",
      fetched_at: 1.day.ago,
      performance: 0.92
    )

    get google_page_speed_results_path(device: "mobile")

    rows = page.css("#device-gaps ~ * li[data-tip]").map { |row| JSON.parse(row["data-tip"]) }
    expect(rows.map { |row| row["title"] }).to eq(["/post/slow", "/post/fast"])
    expect(rows.first["rows"].map { |reading| reading["value"] }).to eq(%w[42 92 50])
  end

  it "plots lab against real readers' LCP, leaving out pages with only the site's figure" do
    Google::PageSpeed::Result.where(page_path: "/post/slow").update_all(lab_lcp_ms: 1800)
    Google::PageSpeed::Result.where(page_path: "/post/fast", strategy: "mobile").update_all(lab_lcp_ms: 1200)

    get google_page_speed_results_path

    tips = page.css("#lcp-lab-field ~ * span[data-tip]").map { |dot| JSON.parse(dot["data-tip"]) }
    expect(tips.map { |tip| [tip["title"], tip["rows"].map { |row| row["value"] }] }).to eq([
      ["/post/slow", ["1.8 s", "4.5 s", "Mobile"]]
    ])
    expect(page.css("#lcp-lab-field ~ * div.ml-14 span.top-1\\.5").map(&:text)).to eq(
      ["0 s", "1.25 s", "2.5 s", "3.75 s", "5 s"]
    )
  end

  it "queues a batch of tests" do
    expect { post sync_google_page_speed_results_path }.to have_enqueued_job(Google::PageSpeed::SyncJob)
    expect(SyncRequest.last).to have_attributes(
      kind: "page_speed",
      limit: Google::PageSpeed::SyncService::DEFAULT_LIMIT
    )
  end

  it "exports the tests as CSV" do
    get google_page_speed_results_path(format: :csv)

    expect(CSV.parse(response.body).size).to eq(4)
  end
end
