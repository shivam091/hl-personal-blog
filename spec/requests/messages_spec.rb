# encoding: UTF-8

require "rails_helper"

RSpec.describe "Messages", type: :request do
  # Shaped like the frontend writes them, so the page reads real data.
  def insert_message(name:, score: 0.9, message: "Hello there", created_at: Time.utc(2026, 9, 1), assessment: nil)
    Message.collection.insert_one({
      "name" => name, "email" => "#{name.downcase}@domain.com", "message" => message,
      "recaptchaScore" => score, "createdAt" => created_at, "recaptchaAssessment" => assessment
    }.compact)
  end

  it "lists messages newest first, with the full text and a reply link" do
    insert_message(name: "Older", created_at: Time.utc(2026, 9, 1))
    insert_message(name: "Newer", message: "Line one\nLine two", created_at: Time.utc(2026, 9, 2))

    get messages_path

    expect(response).to have_http_status(:ok)
    expect(response.body.index("Newer")).to be < response.body.index("Older")
    expect(response.body).to include("Line one\nLine two", "mailto:newer@domain.com?subject=Re%3A%20your%20message")
  end

  it "splits messages by reCAPTCHA score" do
    insert_message(name: "Human", score: 0.9)
    insert_message(name: "Borderline", score: 0.5)

    get messages_path(score: "borderline")
    expect(response.body).to include("Borderline")
    expect(response.body).not_to include("human@domain.com")

    get messages_path(score: "high")
    expect(response.body).to include("human@domain.com")
    expect(response.body).not_to include("borderline@domain.com")
  end

  it "searches messages and senders" do
    insert_message(name: "Ada", message: "Let's collaborate on a talk")
    insert_message(name: "Grace", message: "Typo in your grid post")

    get messages_path(q: "collaborate")
    expect(response.body).to include("ada@domain.com")
    expect(response.body).not_to include("grace@domain.com")

    get messages_path(email: "grace")
    expect(response.body).to include("grace@domain.com")
    expect(response.body).not_to include("ada@domain.com")
  end

  it "paginates on the server" do
    Message.collection.insert_many((1..30).map do |n|
      {"name" => format("Sender%02d", n), "email" => "s#{n}@domain.com", "message" => "Hi", "recaptchaScore" => 0.9, "createdAt" => Time.utc(2026, 9, n)}
    end)

    get messages_path(page: 2)

    expect(response.body.scan(/Sender\d+/).uniq).to eq(%w[Sender05 Sender04 Sender03 Sender02 Sender01])
  end

  it "exports the messages in the selected tab as CSV" do
    insert_message(name: "Human", score: 0.9, message: "Line one\nLine two")
    insert_message(name: "Borderline", score: 0.5)

    get messages_path(format: :csv, score: "high")

    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body)
    expect(rows).to eq([Message::CSV_HEADERS, ["Human", "human@domain.com", "Line one\nLine two", "0.9", nil, "2026-09-01T00:00:00.000Z"]])
  end

  it "shows an empty state" do
    get messages_path
    expect(response.body).to include("No messages yet.")
  end

  it "shows a message with its sender's other messages and newsletter status" do
    insert_message(name: "Ada", message: "First note", created_at: Time.utc(2026, 9, 1))
    insert_message(name: "Ada", message: "Second note", created_at: Time.utc(2026, 9, 2))
    insert_message(name: "Grace", message: "Not Ada's")
    subscriber = NewsletterSubscriber.create!(email: "ADA@domain.com", subscribed_at: Time.utc(2026, 8, 1))

    get message_path(Message.find_by(message: "Second note"))

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#message ~ p").text).to eq("Second note")
    expect(page.at_css("#other-messages ~ ul").text).to include("First note")
    expect(response.body).not_to include("Not Ada")
    expect(page.at_css("a[href='#{newsletter_subscriber_path(subscriber)}']").text).to eq("Subscribed")
  end
end
