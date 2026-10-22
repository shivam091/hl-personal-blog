# encoding: UTF-8

require "rails_helper"

RSpec.describe "Newsletter report's audience and engagement", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says when unsubscribes aren't recorded yet, and when Brevo hasn't posted events" do
    get newsletter_report_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No unsubscribes recorded yet")
    expect(page.at_css("#opens-and-clicks").parent.text).to include("No events from Brevo yet.")
  end

  it "shows sign-ups by form, who left and how, and each mail's opens and clicks" do
    NewsletterSubscriber.create!(email: "a@example.com", subscribed_at: Time.zone.parse("2026-10-01 10:00"), source: "footer", source_page: "/")
    NewsletterUnsubscribe.collection.insert_one("email" => "b@example.com", "subscribedAt" => Time.zone.parse("2026-09-01 10:00"),
      "unsubscribedAt" => Time.zone.parse("2026-10-02 10:00"), "method" => "one_click")
    FeedEntry.create!(url: "https://blog.example.com/post/a", name: "A post", type: "post", published_at: Time.zone.parse("2026-10-02 08:00"),
      last_modified_at: Time.zone.parse("2026-10-02 08:00"), notified_at: Time.zone.parse("2026-10-02 09:00"), notified_count: 2)
    NewsletterEmailEvent.record("event" => "delivered", "email" => "a@example.com", "message-id" => "<a>", "tags" => ["https://blog.example.com/post/a"])
    NewsletterEmailEvent.record("event" => "opened", "email" => "a@example.com", "message-id" => "<a>", "tags" => ["https://blog.example.com/post/a"])

    get newsletter_report_path

    expect(page.at_css("#signups-by-source").parent.text).to include("Footer")
    expect(page.at_css("#unsubscribe-methods").parent.text).to include("One-click, from the mail app")
    expect(page.css("#opens-and-clicks ~ div tbody td").map { |cell| cell.text.squish }.drop(1)).to eq(["2", "1", "1 100.0%", "0 0.0%", "0", "0", "0"])
    split = JSON.parse(page.at_css("#opens-and-clicks ~ div li[data-tip]")["data-tip"])
    expect(split["rows"].map { |row| row["name"] }).to eq(["Clicked · 0 mails", "Opened, no click · 1 mail", "Not opened · 0 mails", "Bounced · 0 mails"])
  end
end
