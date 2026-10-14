# encoding: UTF-8

require "rails_helper"

RSpec.describe "Newsletter subscribers", type: :request do
  # Shaped like the frontend writes them, so the page reads real data.
  before do
    NewsletterSubscriber.collection.insert_many((1..30).map do |n|
      {"email" => format("reader%02d@%s.com", n, n.even? ? "gmail" : "proton"), "subscribedAt" => Time.utc(2026, 9, n)}
    end)
  end

  def emails
    response.body.scan(/reader\d+@\w+\.com/).uniq
  end

  it "lists the newest subscribers first, paginated on the server" do
    get newsletter_subscribers_path

    expect(response).to have_http_status(:ok)
    expect(emails.first).to eq("reader30@gmail.com")
    subscriber = NewsletterSubscriber.find_by(email: "reader30@gmail.com")
    expect(response.body).to include(newsletter_subscriber_path(subscriber))

    get newsletter_subscribers_path(page: 2)
    expect(emails).to eq(%w[reader05@proton.com reader04@gmail.com reader03@proton.com reader02@gmail.com reader01@proton.com])
  end

  it "charts the searched list's size week by week and maps where its subscribers are" do
    NewsletterSubscriber.collection.update_many({"email" => /proton/}, {"$set" => {"country" => "in"}})

    travel_to(Time.zone.parse("2026-10-12 12:00")) { get newsletter_subscribers_path(q: "proton") }

    page = Nokogiri::HTML5(response.body)
    weeks = page.css("#subscriber-growth ~ div rect[data-tip]").map { |hit| JSON.parse(hit["data-tip"]) }
    expect(weeks.first["title"]).to eq("Week 1")
    expect(weeks.map { |week| week["rows"].first["value"] }).to eq(%w[3 7 10 14 15 15 15])
    india = page.css("#subscriber-countries ~ div path").find { |path| JSON.parse(path["data-tip"])["title"] == "🇮🇳 India" }
    expect(JSON.parse(india["data-tip"])["rows"]).to eq([{"value" => "15", "name" => "Subscribers"}])
  end

  it "searches by email and sorts by it" do
    get newsletter_subscribers_path(q: "proton", sort: "email", direction: "asc")

    expect(emails).to all(end_with("@proton.com"))
    expect(emails.first).to eq("reader01@proton.com")
  end

  it "exports every matching subscriber as CSV, not just the current page" do
    get newsletter_subscribers_path(format: :csv, q: "gmail")

    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body)
    expect(rows.first).to eq(NewsletterSubscriber::CSV_HEADERS)
    expect(rows.size).to eq(16)
    expect(rows.second).to eq(["reader30@gmail.com", nil, "2026-09-30T00:00:00.000Z"])
  end

  it "shows an empty state" do
    NewsletterSubscriber.delete_all
    get newsletter_subscribers_path
    expect(response.body).to include("No subscribers yet.")
  end

  it "shows a subscriber with the messages they sent, matched regardless of case" do
    subscriber = NewsletterSubscriber.find_by(email: "reader30@gmail.com")
    Message.collection.insert_many([
      {"name" => "Reader", "email" => "Reader30@Gmail.com", "message" => "Loved the post", "createdAt" => Time.utc(2026, 9, 1)},
      {"name" => "Someone", "email" => "other@domain.com", "message" => "Not theirs", "createdAt" => Time.utc(2026, 9, 2)}
    ])

    get newsletter_subscriber_path(subscriber)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("reader30@gmail.com", "Loved the post")
    expect(response.body).not_to include("Not theirs")
  end

  it "unsubscribes a subscriber from the list" do
    subscriber = NewsletterSubscriber.find_by(email: "reader30@gmail.com")
    get newsletter_subscribers_path
    expect(response.body).to include(%(action="#{newsletter_subscriber_path(subscriber)}"))

    delete newsletter_subscriber_path(subscriber)

    expect(response).to redirect_to(newsletter_subscribers_path)
    expect(flash[:notice]).to eq("Unsubscribed reader30@gmail.com.")
    expect(NewsletterSubscriber.where(id: subscriber.id)).not_to exist
  end
end
