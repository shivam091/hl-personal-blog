# encoding: UTF-8

require "rails_helper"

RSpec.describe "Mixpanel report", type: :request do
  include ActiveJob::TestHelper

  def page
    Nokogiri::HTML5(response.body)
  end

  let(:day) { Period.new({}).to }

  it "says so before anything has synced" do
    get mixpanel_report_path

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("No Mixpanel figures yet.")
  end

  it "shows the period's pages, GA coverage and frustrations" do
    Mixpanel::SiteStat.create!(date: day, visitors: 10, page_views: 14, ga_statuses: {"loaded" => 7, "blocked" => 3},
      themes: {"dark" => 6, "light" => 4}, events: [{"name" => "$mp_web_page_view", "count" => 14}])
    Mixpanel::PageStat.create!(date: day, page_path: "/post/css/grid", content_group: "post", page_views: 14, visitors: 10,
      engaged_views: 12, engaged_seconds: 720, scroll_percent_sum: 900, read_through_views: 6, rage_clicks: 2)
    Mixpanel::IssueStat.create!(date: day, kind: "rage_click", page_path: "/post/css/grid", target: "button#share", count: 2, visitors: 1)

    get mixpanel_report_path

    expect(response).to have_http_status(:ok)
    coverage = page.css("#ga-coverage ~ div tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }
    expect(coverage).to eq([["Loaded", "7", "70.0%"], ["Blocked", "3", "30.0%"]])
    pages = page.css("#pages ~ div tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }
    expect(pages.first.drop(1)).to eq(["14", "10", "1m 00s", "75.0%", "50.0%", "2"])
    expect(page.css("#rage-click ~ div tbody tr td").first.text.strip).to eq("button#share")

    get mixpanel_report_path(format: :csv)
    expect(response.body.lines.second).to start_with("/post/css/grid,post,14,10,12,60.0,0.75,0.5,2,0,0")
  end

  it "queues a sync of the days on screen" do
    expect { post sync_mixpanel_report_path }.to have_enqueued_job(Mixpanel::SyncJob)
  end
end
