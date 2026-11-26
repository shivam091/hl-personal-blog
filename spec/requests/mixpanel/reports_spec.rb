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

  it "shows GA coverage, drop-off, clicks and replays per page" do
    Mixpanel::SiteStat.create!(date: day, visitors: 20, page_views: 20)
    Mixpanel::PageStat.create!(date: day, page_path: "/post/a", content_group: "post", page_views: 20, visitors: 20, engaged_views: 16,
      engaged_seconds: 1600, scroll_percent_sum: 1000, read_through_views: 4, ga_statuses: {"loaded" => 15, "blocked" => 5},
      scroll_reached: {"25" => 15, "50" => 10, "75" => 6, "100" => 4}, reading_times: {"under_15" => 4, "15_60" => 6, "over_180" => 6},
      replays: [{"replay_id" => "rp1", "distinct_id" => "d1", "time" => 1_763_600_000, "seconds" => 300}])
    Mixpanel::ClickStat.create!(date: day, page_path: "/post/a", target: "a.toc → #grid", count: 7, visitors: 5)
    Mixpanel::IssueStat.create!(date: day, kind: "dead_click", page_path: "/post/a", target: "img", count: 2, visitors: 2,
      replays: [{"replay_id" => "rp9", "distinct_id" => "d9", "time" => 1_763_600_000}])
    allow(Rails.application.credentials).to receive(:mixpanel).and_return({project_id: "42"})

    get mixpanel_report_path

    rows = ->(id) { page.css("##{id} ~ div tbody tr").map { |row| row.css("td, th").map { |cell| cell.text.squish } } }
    expect(rows.("ga-coverage-pages")).to eq([["/post/a post", "20", "25.0%", "×1.33"]])
    expect(rows.("drop-off").first).to eq(["/post/a", "20", "75.0%", "50.0%", "30.0%", "20.0%"])
    expect(rows.("clicks")).to eq([["/post/a"], ["a.toc → #grid", "7", "5"]])
    expect(page.css("#least-read ~ div a[href*='replay_id=rp1']").size).to eq(1)
    watch = page.at_css("#dead-click ~ div a[href*='replay_id=rp9']")
    expect(watch["href"]).to eq("https://mixpanel.com/project/42/app/session-replay#replay_id=rp9&distinct_id=d9&time=1763600000")
  end

  it "shows reader preferences, the newsletter form and the subscriber journey" do
    Mixpanel::SiteStat.create!(date: day - 1, visitors: 10, themes: {"dark" => 6, "light" => 4}, color_schemes: {"dark" => 7, "light" => 3},
      reduced_motion: {"reduce" => 1, "no_preference" => 9},
      form_steps: {"seen" => 10, "focused" => 5, "started" => 4, "submitted" => 3, "error" => 1, "subscribed" => 2},
      form_errors: [{"message" => "Invalid email.", "count" => 1}],
      new_subscribers: %w[reader_a reader_b], subscriber_reads: [{"path" => "/post/a", "count" => 2}])
    Mixpanel::SiteStat.create!(date: day, visitors: 3, returning_subscribers: [{"id" => "reader_a", "page_views" => 3}])

    get mixpanel_report_path

    expect(page.css("#system-preferences tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }).to eq([
      ["System colour scheme: Dark", "7", "70.0%"], ["System colour scheme: Light", "3", "30.0%"],
      ["Motion: No preference", "9", "90.0%"], ["Motion: Reduced motion", "1", "10.0%"]
    ])
    form = page.at_css("#newsletter-form").parent.text.squish
    expect(form).to include("Focused the email field", "1 visitor got an error (33.3% of those who submitted).", "Invalid email.")
    journey = page.at_css("#subscriber-journey").parent
    tiles = journey.css("dl > div").to_h { |tile| [tile.at_css("dt").xpath("text()").text.squish, tile.at_css("dd span").text.strip] }
    expect(tiles).to eq("New subscribers" => "2", "Came back" => "50.0%", "Days back" => "1.0")
    expect(journey.text.squish).to include("1 subscriber visited in the period after the day they subscribed, opening 3 pages.")
    expect(journey.css("tbody tr td").map { |cell| cell.text.squish }).to eq(["/post/a", "2"])
  end

  it "queues marking posts and describing events" do
    expect { post annotate_mixpanel_report_path }.to have_enqueued_job(Mixpanel::AnnotationJob)
    expect { post describe_mixpanel_report_path }.to have_enqueued_job(Mixpanel::LexiconJob)
  end

  it "queues a sync of the days on screen" do
    expect { post sync_mixpanel_report_path }.to have_enqueued_job(Mixpanel::SyncJob)
  end
end
