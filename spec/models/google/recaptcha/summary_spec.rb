# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::Summary do
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }

  before do
    Google::Recaptcha::Stat.create!(date: Date.new(2026, 10, 7), scores: [{"score" => 0.1, "count" => 3}, {"score" => 0.9, "count" => 7}])
    Google::Recaptcha::Stat.create!(date: Date.new(2026, 9, 1), scores: [{"score" => 0.1, "count" => 50}])
    Message.collection.insert_many([
      {"name" => "A", "email" => "a@example.com", "country" => "IN", "recaptchaScore" => 0.9, "createdAt" => Time.zone.parse("2026-10-07 10:00")},
      {"name" => "B", "email" => "b@example.com", "country" => "IN", "recaptchaScore" => 0.5, "createdAt" => Time.zone.parse("2026-10-08 10:00")},
      {"name" => "C", "email" => "c@example.com", "createdAt" => Time.zone.parse("2026-10-08 10:00")}
    ])
  end

  subject(:summary) { described_class.new(period) }

  it "adds up the period's score buckets, lowest first" do
    expect(summary.histogram.values_at(0.1, 0.9)).to eq([3, 7])
    expect(summary.histogram.keys.first).to eq(0.0)
    expect(summary.low_score_share).to eq(0.3)
  end

  it "buckets contact messages by score and groups them by country" do
    expect(summary.message_histogram.values_at(0.5, 0.9)).to eq([1, 1])
    expect(summary.messages_by_country).to eq([["IN", 2, 0.7], ["ZZ", 1, nil]])
  end
end
