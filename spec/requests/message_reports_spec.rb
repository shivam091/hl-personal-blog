# encoding: UTF-8

require "rails_helper"

RSpec.describe "Messages report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  def message(name, score:, created_at: Time.zone.parse("2026-10-05 10:00"), assessment: "projects/p/assessments/#{name}")
    id = Message.collection.insert_one({
      "name" => name,
      "email" => "#{name.downcase}@domain.com",
      "message" => "Hello from #{name}",
      "recaptchaScore" => score,
      "country" => "IN",
      "createdAt" => created_at,
      "recaptchaAssessment" => assessment
    }.compact).inserted_id
    Message.find(id)
  end

  it "shows verdicts, feedback to Google, thresholds and who's waiting" do
    MessageReview.create!(message_id: message("Ada", score: 0.9).id, verdict: "genuine", annotated_at: Time.current)
    MessageReview.create!(message_id: message("Bot", score: 0.5).id, verdict: "spam", annotation_error: "403 Forbidden")
    message("Eve", score: 0.7)

    get message_report_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#messages-by-verdict")).to be_present
    feedback = page.at_css("[aria-labelledby=google-feedback]").text.squish
    expect(feedback).to include("Reported to Google 1", "Failed to send 1", "Not marked yet 1", "403 Forbidden")
    current = page.css("[aria-labelledby=threshold-check] tbody tr").find { |row| row.text.include?("now") }
    expect(current.css("td").map { |cell| cell.text.squish }).to eq(["0.5 now", "0", "0", "0", "1"])
    expect(page.at_css("[aria-labelledby=waiting]").text).to include("Eve")
    expect(page.at_css("[aria-labelledby=waiting]").text).not_to include("Ada")
    india = page.css("[aria-labelledby=messages-by-country] path[data-tip]").find { |path| JSON.parse(path["data-tip"])["title"] == "🇮🇳 India" }
    expect(JSON.parse(india["data-tip"])["rows"].first["value"]).to eq("3")
  end

  it "says when the period has no messages" do
    get message_report_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("No messages in")
    expect(page.at_css("#messages-by-verdict")).to be_nil
  end

  it "exports each message with its verdict and whether Google heard" do
    MessageReview.create!(
      message_id: message("Ada", score: 0.9).id,
      verdict: "genuine",
      annotated_at: Time.zone.parse("2026-10-06 09:00")
    )

    get message_report_path(format: :csv)

    rows = CSV.parse(response.body)
    expect(rows.first).to eq(MessageStats::CSV_HEADERS)
    expect(rows.second).to include("Ada", "ada@domain.com", "0.9", "projects/p/assessments/Ada", "Genuine", "2026-10-06T03:30:00.000Z")
    expect(ExportRequest.count).to eq(1)
  end
end
