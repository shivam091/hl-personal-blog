# encoding: UTF-8

require "rails_helper"

RSpec.describe MessageStats do
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-10"}) }

  def message(name, score:, day: 5, country: "IN", assessment: "projects/p/assessments/#{name}", email: nil)
    id = Message.collection.insert_one({
      "name" => name,
      "email" => (email || "#{name.downcase}@domain.com"),
      "message" => "Hi",
      "recaptchaScore" => score,
      "country" => country,
      "createdAt" => Time.zone.local(2026, 10, day, 12),
      "recaptchaAssessment" => assessment
    }.compact).inserted_id
    Message.find(id)
  end

  def review(message, verdict, **attributes)
    MessageReview.create!(message_id: message.id, verdict: verdict, **attributes)
  end

  it "splits messages by verdict and by where their feedback to Google stands" do
    review(message("Ada", score: 0.9), "genuine", annotated_at: Time.current)
    review(message("Bot", score: 0.5), "spam", annotation_error: "403 Forbidden")
    review(message("Old", score: 0.7, assessment: nil), "genuine", annotation_error: "No reCAPTCHA assessment was kept with this message")
    review(message("New", score: 0.8), "spam")
    message("Eve", score: 0.6)
    message("Out", score: 0.9, day: 20)

    stats = described_class.new(period)

    expect(stats.total).to eq(5)
    expect([stats.count("genuine"), stats.count("spam"), stats.unmarked]).to eq([2, 2, 1])
    expect(stats.spam_share).to eq(0.5)
    expect(stats.feedback).to eq(reported: 1, failed: 1, unreportable: 1, sending: 1, unmarked: 1)
    expect(stats.feedback_errors).to eq([["403 Forbidden", 1]])
    expect(stats.assessed).to eq(4)
  end

  it "tries stricter thresholds against what's been marked" do
    review(message("Ada", score: 0.9), "genuine")
    review(message("Bea", score: 0.6), "genuine")
    review(message("Bot", score: 0.5), "spam")
    review(message("Spam", score: 0.7), "spam")

    thresholds = described_class.new(period).thresholds.index_by(&:score)

    expect(thresholds[0.5]).to have_attributes(blocked: 0, genuine_lost: 0, spam_caught: 0, spam_through: 2, current?: true)
    expect(thresholds[0.7]).to have_attributes(blocked: 2, genuine_lost: 1, spam_caught: 1, spam_through: 1)
    expect(thresholds[0.8]).to have_attributes(blocked: 3, genuine_lost: 1, spam_caught: 2, spam_through: 0)
  end

  it "bands scores in tenths from the form's threshold up, keeping lower ones only when present" do
    review(message("Ada", score: 0.9), "genuine")
    review(message("Bot", score: 0.7), "spam")
    message("Eve", score: 0.7)

    bands = described_class.new(period).bands.index_by(&:label)

    expect(bands.keys).to eq(%w[0.5 0.6 0.7 0.8 0.9])
    expect(bands["0.7"]).to have_attributes(messages: 2, genuine: 0, spam: 1, unmarked: 1, spam_share: 1.0)
    expect(bands["0.5"].spam_share).to be_nil
  end

  it "lays messages out day by day, with empty days kept" do
    review(message("Ada", score: 0.9, day: 2), "genuine")
    message("Eve", score: 0.6, day: 2)

    keys, counts = described_class.new(period).timeline

    expect(keys.size).to eq(10)
    expect(counts["genuine"][1]).to eq(1)
    expect(counts["unmarked"][1]).to eq(1)
    expect(counts["spam"].sum).to eq(0)
  end

  it "lists unmarked messages oldest first, and people who wrote more than once" do
    message("Late", score: 0.9, day: 9)
    message("Early", score: 0.9, day: 1, email: "same@domain.com")
    review(message("Again", score: 0.6, day: 3, email: "SAME@domain.com"), "spam")

    stats = described_class.new(period)

    expect(stats.waiting.map(&:name)).to eq(%w[Early Late])
    expect(stats.repeat_senders.sole).to have_attributes(email: "same@domain.com", messages: 2, spam: 1, genuine: 0)
  end

  it "narrows to a country" do
    message("Ada", score: 0.9, country: "in")
    message("Bob", score: 0.9, country: "US")

    expect(described_class.new(period, country: "IN").total).to eq(1)
    expect(described_class.new(period).by_country.map(&:country)).to eq(%w[IN US])
    expect(described_class.new(period).by_country(limit: 1).map(&:country)).to eq(%w[IN])
    expect(described_class.new(period).by_country(limit: nil).size).to eq(2)
  end
end
