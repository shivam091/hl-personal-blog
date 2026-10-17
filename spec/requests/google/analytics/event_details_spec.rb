# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics event", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }
  let(:realtime) { Google::Analytics::RealtimeService::EventSnapshot.new(2, {"IN" => 2}, []) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  before do
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "click", event_count: 5, total_users: 3, active_users: 2)
    Google::Analytics::EventStat.create!(date: yesterday - 1, page_path: "/post/b", event_name: "click", event_count: 3, total_users: 2, active_users: 1)
    Google::Analytics::EventStat.create!(date: yesterday, page_path: "/post/a", event_name: "scroll", event_count: 9, total_users: 4, active_users: 4)
    allow(Google::Analytics::RealtimeService).to receive(:event) { realtime }
  end

  def page
    Nokogiri::HTML5(response.body)
  end

  def tiles
    page.css("dl > div").to_h { |tile| [tile.at_css("dt").xpath("text()").text.squish, tile.css("dd").first.text.squish] }
  end

  it "says from when the event was first recorded, only while the period reaches back before it" do
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_event_path("click", from: "2026-10-01", to: yesterday.iso8601)
    expect(page.at_css("[role=note]").text.squish).to eq(
      "click events are counted from 11 Oct, 2026, the first day Google Analytics recorded one, so earlier days in this period have none."
    )

    get google_analytics_event_path("click", from: (yesterday - 1).iso8601, to: yesterday.iso8601)
    expect(page.text).not_to include("are counted from")
  end

  it "says when Analytics began for an event it has had from its first day" do
    Google::Analytics::EventStat.create!(date: Date.new(2026, 6, 18), page_path: "/", event_name: "scroll", event_count: 1)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_event_path("scroll", from: "2026-06-01", to: yesterday.iso8601)

    expect(page.text.squish).to include("Analytics figures are counted from 18 Jun, 2026, two days after the blog went live on 16 Jun, 2026")
  end

  it "sets each page's events against the period compared with, only once one is picked" do
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")
    Google::Analytics::EventStat.create!(date: yesterday - 55, page_path: "/post/a", event_name: "click", event_count: 2)

    get google_analytics_event_path("click")

    row = page.css("section[aria-labelledby=pages] tbody tr").find { |tr| tr.text.include?("/post/a") }
    expect(row.text.squish).to include("5 (+150%)")

    get google_analytics_event_path("click", compare: "off")

    expect(page.css("section[aria-labelledby=pages] tbody").text).not_to include("%)")
  end

  it "opens from the event's name in the Engagement report, keeping the period" do
    get google_analytics_engagement_breakdown_path("events", from: (yesterday - 6).iso8601, to: yesterday.iso8601)

    expect(page.at_css("tbody a[title='Open click']")["href"])
      .to eq(google_analytics_event_path("click", from: (yesterday - 6).iso8601, to: yesterday.iso8601))
  end

  it "shows only the event's stored figures, by page, when GA can't be asked, and says so" do
    get google_analytics_event_path("click")

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to eq("click")
    expect(tiles).to include("Event count" => "8", "Total users" => "5", "Events per session" => "—")
    expect(page.css("[aria-labelledby=pages] tbody tr").map { |row| row.css("td").first(2).map(&:text) })
      .to eq([["/post/a", "5"], ["/post/b", "3"]])
    expect(page.text.squish).to include("Couldn't get the event's users, sessions and countries from Google Analytics (not asked in specs)")
    expect(page.at_css("[aria-labelledby=countries]").text).to include("couldn't be asked")
  end

  it "asks GA for the event's users, sessions and countries, narrowed to it" do
    allow(Google::Analytics::LiveFigures).to receive(:call) do |dimensions:, metrics:, filters:, **|
      raise "not narrowed" unless filters == [["eventName", "EXACT", "click"]]

      case dimensions
      when {} then Google::Analytics::LiveFigures::Result.new(rows: {}, total: {total_users: 4, active_users: 3, sessions: 2})
      when {country: "countryId"} then Google::Analytics::LiveFigures::Result.new(rows: {%w[IN] => {event_count: 6}, %w[US] => {event_count: 2}}, total: {})
      else Google::Analytics::LiveFigures::Result.new(rows: {[yesterday.strftime("%Y%m%d")] => {event_count: 5, sessions: 1}}, total: {})
      end
    end

    get google_analytics_event_path("click")

    expect(tiles).to include("Event count" => "8", "Total users" => "4", "Active users" => "3", "Events per session" => "4.00")
    expect(page.css("[aria-labelledby=countries] tbody tr td:first-child").map(&:text)).to eq(["🇮🇳 IN", "🇺🇸 US"])
    expect(page.at_css("[aria-labelledby=events-per-session-over-time] svg")).to be_present
    expect(page.text).not_to include("Couldn't get")
  end

  it "shows the event's triggers in the last 30 minutes" do
    get google_analytics_event_path("click")

    card = page.at_css("[aria-labelledby=realtime]")
    expect(card.at_css("p").text).to eq("2")
    expect(card.at_css("tbody td").text).to eq("🇮🇳 IN")
    expect(Google::Analytics::RealtimeService).to have_received(:event).with("click")
  end

  it "takes event names with dots" do
    get "/google/analytics/engagement/events/file.download"

    expect(response).to have_http_status(:ok)
    expect(page.at_css("h1").text).to eq("file.download")
  end

  it "says when the event wasn't triggered in the period" do
    get google_analytics_event_path("sign_up")

    expect(page.at_css("[aria-labelledby=event-count-over-time]").text).to include("No sign_up events in")
  end
end
