# encoding: UTF-8

require "rails_helper"

RSpec.describe "Messages", type: :request do
  def insert_message(name:, score: 0.9, message: "Hello there", created_at: Time.utc(2026, 9, 1), assessment: nil)
    Message.collection.insert_one({
      "name" => name, "email" => "#{name.downcase}@domain.com", "message" => message,
      "recaptchaScore" => score, "createdAt" => created_at, "recaptchaAssessment" => assessment
    }.compact)
  end

  describe "marking a message as spam or genuine" do
    include ActiveJob::TestHelper

    it "keeps the verdict apart from the message and queues reporting it to reCAPTCHA" do
      id = insert_message(name: "Bot", assessment: "projects/123/assessments/abc").inserted_id

      expect { patch review_message_path(id, verdict: "spam") }.to have_enqueued_job(Google::Recaptcha::AnnotateMessageJob)
      expect(response).to redirect_to(message_path(id))
      expect(flash[:notice]).to eq("Marked the message from Bot as spam and reporting it to reCAPTCHA.")
      expect(MessageReview.all.to_a.sole).to have_attributes(message_id: id, verdict: "spam", annotated_at: nil)
      expect(Message.find(id).attributes).not_to have_key("verdict")

      get message_path(id)
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("button[aria-pressed=true]").text.squish).to eq("Spam")
      expect(page.at_css("#message-feedback").text).to eq("Sending to reCAPTCHA…")
    end

    it "changes a verdict in place, sending the new one" do
      id = insert_message(name: "Ada", assessment: "projects/123/assessments/abc").inserted_id
      patch review_message_path(id, verdict: "spam")

      expect { patch review_message_path(id, verdict: "genuine") }.to have_enqueued_job(Google::Recaptcha::AnnotateMessageJob)
      expect(MessageReview.all.to_a.sole.verdict).to eq("genuine")
    end

    it "marks a message checked without an assessment, saying it can't be reported" do
      id = insert_message(name: "Ada").inserted_id

      patch review_message_path(id, verdict: "genuine")
      expect(flash[:notice]).to include("not reported to reCAPTCHA: no assessment was kept with it")

      get message_path(id)
      expect(Nokogiri::HTML5(response.body).at_css("#message-feedback").text).to eq("Not sent: no reCAPTCHA assessment was kept with this message")
    end

    it "refuses an unknown verdict" do
      id = insert_message(name: "Ada").inserted_id

      patch review_message_path(id, verdict: "maybe"), headers: {"HTTP_REFERER" => messages_url}
      expect(response).to redirect_to(messages_url)
      expect(MessageReview.count).to eq(0)
    end

    it "badges each marked message in the list, with both verdicts offered" do
      id = insert_message(name: "Bot").inserted_id
      insert_message(name: "Ada")
      patch review_message_path(id, verdict: "spam")

      get messages_path
      page = Nokogiri::HTML5(response.body)
      expect(page.css("tbody span.bg-red-100").map(&:text)).to eq(["Spam"])
      buttons = page.css("tbody form button")
      expect(buttons.map { |button| button.text.squish }.uniq).to eq([""])
      expect(buttons.map { |button| button["title"] }.tally)
        .to eq("Mark as genuine" => 2, "Mark as spam" => 1, "Marked as spam" => 1)
      expect(buttons.map { |button| button["aria-label"] }).to include("Marked as spam: message from Bot")
    end
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
