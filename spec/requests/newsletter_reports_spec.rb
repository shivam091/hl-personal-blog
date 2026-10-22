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
    october = page.css("#sends-by-month ~ div g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }.last
    expect([october["title"], october["rows"].first["value"]]).to eq(["October 2026", "3"])
  end
end
