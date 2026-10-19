# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics Web Vitals (readers)", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  def vital(path, metric, rating, count, sum, date: yesterday)
    Google::Analytics::WebVitalStat.create!(date: date, page_path: path, metric: metric, rating: rating, event_count: count, value_sum: sum)
  end

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    vital("/post/a", "LCP", "good", 8, 16_000)
    vital("/post/a", "LCP", "poor", 2, 10_000)
    vital("/post/b", "LCP", "needs-improvement", 4, 12_000)
    vital("/post/a", "CLS", "good", 5, 0.25)
  end

  it "shows LCP at the bare path, page by page, with every metric's bands above" do
    get google_analytics_web_vitals_path

    expect(response).to have_http_status(:ok)
    overview = page.css("section[aria-labelledby=web-vitals-overview] tbody tr").map { |row| row.text.squish }
    expect(overview.first).to include("LCP", "57.1%", "14.3%", "2,714 ms", "14")
    expect(overview.third).to include("CLS", "0.05")
    rows = page.css("#web-vitals-overview ~ * tbody tr, main > div.relative tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish } }
    expect(rows.last(2).map { |cells| cells.drop(2).first(2) }).to include(["/post/a", "10"], ["/post/b", "4"])
  end

  it "sets each metric's reports and mean against the period compared with, only once one is picked" do
    vital("/post/a", "LCP", "good", 4, 4_000, date: yesterday - 55)

    get google_analytics_web_vitals_path

    overview = page.css("section[aria-labelledby=web-vitals-overview] tbody tr").first.text.squish
    expect(overview).to include("2,714 ms (+171.4%)", "14 (+250%)")

    get google_analytics_web_vitals_path(compare: "off")

    expect(page.css("section[aria-labelledby=web-vitals-overview] tbody tr").first.text).not_to include("%)")
  end

  it "opens each metric as its own tab, its mean in the metric's own units" do
    get google_analytics_web_vitals_breakdown_path("cls")

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("0.05")
  end

  it "exports the page totals as CSV" do
    get google_analytics_web_vitals_path(format: :csv)

    csv = CSV.parse(response.body, headers: true)
    expect(csv.headers).to eq(["Page path", "Reports", "Good", "Needs improvement", "Poor", "Mean"])
    expect(csv.find { |row| row["Page path"] == "/post/b" }.to_h.values_at("Reports", "Poor", "Mean")).to eq(["4", "0.0", "3000.0"])
  end

  it "404s a metric the blog doesn't send" do
    get google_analytics_web_vitals_breakdown_path("fid")

    expect(response).to have_http_status(:not_found)
  end
end
