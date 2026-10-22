# encoding: UTF-8

require "rails_helper"

RSpec.describe "Newsletter report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "shows empty states with no entries or sends" do
    get newsletter_report_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#signups-around-entries").parent.text).to include("Nothing published in")
    expect(page.at_css("#failure-reasons").parent.text).to include("No undelivered emails waiting.")
  end

  it "lists each entry's sign-ups either side of publishing, and the month's sends" do
    FeedEntry.create!(url: "https://blog.example.com/post/a", name: "A post", type: "post",
      published_at: Time.zone.parse("2026-10-02 08:00"), last_modified_at: Time.zone.parse("2026-10-02 08:00"),
      notified_at: Time.zone.parse("2026-10-02 09:00"), notified_count: 3)
    NewsletterSubscriber.create!(email: "reader@example.com", subscribed_at: Time.zone.parse("2026-10-03 10:00"))

    get newsletter_report_path

    expect(page.css("#signups-around-entries ~ div tbody td").map { |cell| cell.text.squish }).to eq(["A post", "2 Oct, 2026", "0", "1", "+1"])
    week = page.css("#sends ~ div g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.find { |bar| bar["title"] == "Week of 28 Sep, 2026" }
    expect(week["rows"].first["value"]).to eq("3")
  end

  it "counts emails sent in the chosen period only, against the period before" do
    FeedEntry.create!(url: "https://blog.example.com/post/a", name: "A post", type: "post",
      published_at: Time.zone.parse("2026-10-02 08:00"), last_modified_at: Time.zone.parse("2026-10-02 08:00"),
      notified_at: Time.zone.parse("2026-10-02 09:00"), notified_count: 3)
    FeedEntry.create!(url: "https://blog.example.com/post/old", name: "Old post", type: "post",
      published_at: Time.zone.parse("2026-05-02 08:00"), last_modified_at: Time.zone.parse("2026-05-02 08:00"),
      notified_at: Time.zone.parse("2026-05-02 09:00"), notified_count: 9)

    get newsletter_report_path(from: "2026-10-01", to: "2026-10-11")

    sent = page.css("dl > div").find { |tile| tile.at_css("dt").text.include?("Emails sent") }
    expect(sent.at_css("dd span").text.strip).to eq("3")
    expect(sent.at_css("dd[title]")["title"]).to eq("Compared with 20 Sep, 2026 – 30 Sep, 2026")
  end

  it "filters by country and exports as CSV" do
    NewsletterSubscriber.create!(email: "in@example.com", country: "IN", subscribed_at: Time.zone.parse("2026-10-05 10:00"))
    NewsletterSubscriber.create!(email: "us@example.com", country: "US", subscribed_at: Time.zone.parse("2026-10-05 10:00"))

    get newsletter_report_path(country: "IN")

    tiles = page.css("dl > div").to_h { |tile| [tile.at_css("dt").xpath("text()").text.squish, tile.at_css("dd span").text.strip] }
    expect(tiles.values_at("List size", "New subscribers")).to eq(%w[1 1])
    expect(page.at_css("#period-country a[aria-current]").text.squish).to include("IN")

    get newsletter_report_path(format: :csv, export: "sends", country: "IN")

    expect(response.media_type).to eq("text/csv")
    expect(CSV.parse(response.body).first).to eq(["Week starting", "Sent", "Undelivered"])
    expect(ExportRequest.count).to eq(1)
  end
end
