# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterAudience do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-10"}, today: today) }
  let(:audience) { described_class.new(period) }

  def subscriber(at, source: nil, page: nil)
    NewsletterSubscriber.create!(email: "#{SecureRandom.hex(4)}@example.com", subscribed_at: Time.zone.parse(at), source: source, source_page: page)
  end

  def left(subscribed, unsubscribed, method: "link", source: nil, page: nil)
    NewsletterUnsubscribe.collection.insert_one("email" => "#{SecureRandom.hex(4)}@example.com", "subscribedAt" => subscribed && Time.zone.parse(subscribed),
      "unsubscribedAt" => Time.zone.parse(unsubscribed), "method" => method, "source" => source, "sourcePage" => page)
  end

  it "counts sign-ups by form and by page, those who've left since included" do
    subscriber("2026-10-02 10:00", source: "footer", page: "/")
    subscriber("2026-10-03 10:00", source: "article_end", page: "/post/a")
    subscriber("2026-10-04 10:00")
    subscriber("2026-09-20 10:00", source: "footer", page: "/")
    left("2026-10-05 10:00", "2026-10-06 10:00", source: "article_end", page: "/post/a")

    expect(audience.signups_by_source).to eq("Footer" => 1, "End of an article" => 2, "Unknown" => 1)
    expect(audience.signups_by_page).to eq("/post/a" => 2, "/" => 1, "Unknown" => 1)
  end

  it "works out churn from everyone on the list as the period began" do
    left("2026-08-01 10:00", "2026-09-15 10:00")
    3.times { subscriber("2026-09-01 10:00") }
    left("2026-09-10 10:00", "2026-10-03 10:00", method: "one_click")
    left("2026-10-02 10:00", "2026-10-02 12:00")
    subscriber("2026-10-05 10:00")

    expect(audience.unsubscribe_count).to eq(2)
    expect(audience.churn_rate).to eq(0.5)
    expect(audience.by_method).to eq("One-click, from the mail app" => 1, "Unsubscribe page" => 1)
    expect(audience.stays).to include("Within a day" => 1, "Within a month" => 1, "Unknown" => 0)
    expect(audience.median_days_subscribed).to eq(12)
    expect(audience.weekly_unsubscribes).to eq([[Date.new(2026, 9, 28), 2], [Date.new(2026, 10, 5), 0]])
  end

  it "has no churn rate for a period starting before leaving was recorded" do
    left("2026-09-10 10:00", "2026-10-03 10:00")

    expect(audience.counted_since).to eq(Date.new(2026, 10, 3))
    expect(audience.churn_rate).to be_nil
  end
end
