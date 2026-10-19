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
    expect(page.css("#daily, #ga-status-trend, #engagement-trend, #frustration-trend").size).to eq(4)
    expect(response.body).to include("Share GA can't see")

    get mixpanel_report_path(format: :csv)
    expect(response.body.lines.second).to start_with("/post/css/grid,post,14,10,12,60.0,0.75,0.5,2,0,0")
  end

  it "divides each bucket's sums rather than averaging its days" do
    period = Period.new({from: "2026-11-02", to: "2026-11-15"})
    Mixpanel::SiteStat.create!(date: Date.new(2026, 11, 2), ga_statuses: {"loaded" => 9, "blocked" => 1})
    Mixpanel::SiteStat.create!(date: Date.new(2026, 11, 3), ga_statuses: {"blocked" => 1})
    Mixpanel::PageStat.create!(date: Date.new(2026, 11, 2), page_path: "/a", engaged_views: 9, engaged_seconds: 90)
    Mixpanel::PageStat.create!(date: Date.new(2026, 11, 3), page_path: "/a", engaged_views: 1, engaged_seconds: 110)
    report = Mixpanel::Report.new(period)

    weekly = ChartGranularity.new({by: "week"}, period: period)
    expect(report.mean_engaged_seconds_by(weekly)).to eq([20.0, nil])
    expect(report.blocked_percent_by(weekly)).to eq([18.2, nil])
    daily = ChartGranularity.new({}, period: period)
    expect(report.mean_engaged_seconds_by(daily)).to eq([10.0, 110.0, *Array.new(12)])
  end

  it "shows the funnel and the retention cohorts" do
    Mixpanel::SiteStat.create!(date: day, visitors: 10, funnel: {"viewed" => 10, "read" => 4, "form_seen" => 3, "form_started" => 2, "subscribed" => 1})
    Mixpanel::RetentionCohort.create!(cohort_date: Date.current - 14, first: 10, counts: [10, 3])

    get mixpanel_report_path

    expect(page.css("#funnel ~ div").text).to include("Viewed a page", "Subscribed")
    expect(page.css("#retention ~ div td div").map { |cell| cell.text.strip }.reject(&:empty?)).to eq(["30%"])
  end

  it "queues marking posts and describing events" do
    expect { post annotate_mixpanel_report_path }.to have_enqueued_job(Mixpanel::AnnotationJob)
    expect { post describe_mixpanel_report_path }.to have_enqueued_job(Mixpanel::LexiconJob)
  end

  it "queues a sync of the days on screen" do
    expect { post sync_mixpanel_report_path }.to have_enqueued_job(Mixpanel::SyncJob)
  end
end
