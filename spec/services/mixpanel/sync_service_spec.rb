# encoding: UTF-8

require "rails_helper"

RSpec.describe Mixpanel::SyncService do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:day) { Date.new(2026, 11, 20) }
  let(:requests) { [] }

  def client
    connection = Faraday.new(url: "https://data.mixpanel.com") do |faraday|
      faraday.response :raise_error
      faraday.adapter :test, stubs
    end
    Mixpanel::Client.new(project_id: "123", username: "sa", secret: "secret", connection: connection)
  end

  def event(name, **properties)
    {event: name, properties: {distinct_id: "reader-1", **properties}}
  end

  def export(*events)
    events.map(&:to_json).join("\n")
  end

  def sync(days: 1)
    described_class.call(days: days, to: day, client: client, retention: nil, host: "blog.example.com")
  end

  it "adds up each page's views, engaged time, scroll depth and frustration for the day" do
    url = "https://blog.example.com/post/css/grid/"
    stubs.get("/api/2.0/export") do |env|
      requests << env.params
      [200, {}, export(
        event("$mp_web_page_view", "$current_url": url, content_group: "post", ga_status: "blocked", theme: "dark", "$mp_replay_id": "r1"),
        event("$mp_web_page_view", distinct_id: "reader-2", "$current_url": url, ga_status: "loaded", theme: "light"),
        # Resent with growing totals when the tab is hidden, then on leaving.
        event("page_leave", path: "/post/css/grid", view_id: "v1", engaged_seconds: 40, max_scroll_percent: 60),
        event("page_leave", path: "/post/css/grid", view_id: "v1", engaged_seconds: 95, max_scroll_percent: 100),
        event("page_leave", distinct_id: "reader-2", path: "/post/css/grid", view_id: "v2", engaged_seconds: 5, max_scroll_percent: 20),
        event("$mp_rage_click", "$current_url": url, "$el_tag_name": "button", "$el_id": "share", "$el_classes": ["icon"]),
        event("$mp_rage_click", "$current_url": url, "$el_tag_name": "button", "$el_id": "share", "$el_classes": ["icon"]),
        event("js_error", path: "/post/css/grid", error_message: "x is undefined", error_source: "https://blog.example.com/_next/app.js", error_line: 12),
        event("$mp_click", "$current_url": "https://blog.example.com/about"),
        event("newsletter_subscribe", distinct_id: "reader-1", source: "server")
      )]
    end

    expect(sync.errors).to eq([])
    expect(requests.first).to include("project_id" => "123", "from_date" => "2026-11-20", "to_date" => "2026-11-20")

    page = Mixpanel::PageStat.find_by(date: day, page_path: "/post/css/grid")
    expect(page).to have_attributes(
      content_group: "post", page_views: 2, visitors: 2, engaged_views: 2, engaged_seconds: 100,
      scroll_percent_sum: 120, read_through_views: 1, rage_clicks: 2, dead_clicks: 0, js_errors: 1
    )
    expect(Mixpanel::PageStat.where(page_path: "/about")).not_to exist

    site = Mixpanel::SiteStat.find_by(date: day)
    expect(site).to have_attributes(visitors: 2, page_views: 2, replays: 1)
    expect(site.ga_statuses).to eq({"blocked" => 1, "loaded" => 1})
    expect(site.themes).to eq({"dark" => 1, "light" => 1})
    expect(site.events.first).to eq({"name" => "page_leave", "count" => 3})

    expect(Mixpanel::IssueStat.where(date: day).map { |issue| [issue.kind, issue.target, issue.count, issue.visitors] }).to contain_exactly(
      ["rage_click", "button#share.icon", 2, 1],
      ["js_error", "x is undefined (app.js:12)", 1, 1]
    )
  end

  it "counts the day's visitors at each step who took every step before it" do
    stubs.get("/api/2.0/export") do
      [200, {}, export(
        event("$mp_web_page_view", "$device_id": "d1"), event("article_read", "$device_id": "d1"),
        event("newsletter_form_seen", "$device_id": "d1"), event("newsletter_form_started", "$device_id": "d1"),
        # The server names a subscriber by their id, with the same device.
        event("newsletter_subscribe", distinct_id: "reader_abc", "$device_id": "d1", source: "server"),
        event("$mp_web_page_view", distinct_id: "reader-2", "$device_id": "d2"), event("newsletter_form_seen", "$device_id": "d2"),
        event("$mp_web_page_view", distinct_id: "reader-3", "$device_id": "d3"), event("article_read", "$device_id": "d3")
      )]
    end

    sync
    expect(Mixpanel::SiteStat.find_by(date: day).funnel).to eq(
      {"viewed" => 3, "read" => 2, "form_seen" => 1, "form_started" => 1, "subscribed" => 1}
    )
  end

  it "counts only the live blog's traffic, not a local run or a preview deploy" do
    stubs.get("/api/2.0/export") do
      [200, {}, export(
        event("$mp_web_page_view", "$current_url": "https://blog.example.com/post/a"),
        event("$mp_web_page_view", distinct_id: "dev", "$current_url": "http://localhost:3001/post/a"),
        event("$mp_web_page_view", distinct_id: "preview", "$current_url": "https://blog-git-feat-x.vercel.app/post/a"),
        event("newsletter_subscribe", distinct_id: "reader-1", source: "server")
      )]
    end

    sync
    site = Mixpanel::SiteStat.find_by(date: day)
    expect(site).to have_attributes(visitors: 1, page_views: 1)
    expect(site.events).to contain_exactly({"name" => "$mp_web_page_view", "count" => 1}, {"name" => "newsletter_subscribe", "count" => 1})
    expect(Mixpanel::PageStat.find_by(date: day, page_path: "/post/a").page_views).to eq(1)
  end

  it "updates the day in place when it's synced again" do
    stubs.get("/api/2.0/export") { [200, {}, export(event("$mp_web_page_view", "$current_url": "https://blog.example.com/"))] }

    sync
    result = sync
    expect(result.summary).to eq("0 created, 0 updated, 2 unchanged, 0 failed")
    expect(Mixpanel::PageStat.find_by(date: day, page_path: "/").page_views).to eq(1)
  end

  it "names the region as the likely cause when Mixpanel cuts the export short" do
    stubs.get("/api/2.0/export") { [200, {}, "terminated early\n"] }

    expect(sync.errors.first).to start_with('Mixpanel 2026-11-20: Mixpanel cut the export short ("terminated early"), which it does when data_host')
  end

  it "fetches each day on its own and stops at a refused login" do
    stubs.get("/api/2.0/export") do |env|
      requests << env.params["from_date"]
      [401, {}, {error: "Invalid credentials"}.to_json]
    end

    result = sync(days: 3)
    expect(result.errors).to eq(["Mixpanel 2026-11-18: Invalid credentials"])
    expect(requests).to eq(["2026-11-18"])
  end

  it "says so when credentials are missing" do
    unconfigured = Mixpanel::Client.new(project_id: nil, username: nil, secret: nil)

    expect(described_class.call(client: unconfigured).errors).to eq([Mixpanel::Client::NOT_CONFIGURED])
  end
end
