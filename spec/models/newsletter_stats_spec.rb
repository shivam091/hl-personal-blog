# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterStats do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-11"}, today: today) }

  subject(:stats) { described_class.new(period, today: today) }

  def subscribe(at)
    NewsletterSubscriber.create!(email: "#{SecureRandom.hex(4)}@example.com", subscribed_at: Time.zone.parse(at))
  end

  def publish(path, at, **attributes)
    FeedEntry.create!(url: "https://blog.example.com#{path}", name: path, type: "post", published_at: Time.zone.parse(at),
      last_modified_at: Time.zone.parse(at), **attributes)
  end

  it "counts the list and the period's sign-ups" do
    subscribe("2026-09-20 10:00")
    subscribe("2026-10-05 10:00")

    expect(stats.list_size).to eq(2)
    expect(stats.new_subscribers).to eq(1)
  end

  it "sets each entry's week of sign-ups against the week before" do
    publish("/post/a", "2026-10-02 08:00")
    publish("/post/b", "2026-10-09 08:00")
    subscribe("2026-09-28 10:00")
    subscribe("2026-10-02 18:00")
    subscribe("2026-10-03 10:00")
    subscribe("2026-10-10 10:00")

    b, a = stats.signups_around_entries

    expect([a.entry.url, a.before, a.after, a.change, a.complete]).to eq(["https://blog.example.com/post/a", 1, 2, 1, true])
    expect([b.before, b.after, b.complete]).to eq([2, 1, false])
  end

  it "sums sends by month and groups what's still undelivered by error" do
    publish("/post/a", "2026-09-02 08:00", notified_at: Time.zone.parse("2026-09-02 09:00"), notified_count: 5,
      notification_failures: [{"email" => "x@example.com", "error" => "Net::SMTPFatalError: 550 no such user"},
        {"email" => "y@example.com", "error" => "Net::ReadTimeout: timed out"}])

    september = stats.sends.find { |month| month.month == Date.new(2026, 9, 1) }

    expect(stats.sends.size).to eq(12)
    expect([september.sent, september.undelivered]).to eq([5, 2])
    expect(stats.undelivered).to eq(2)
    expect(stats.failure_reasons).to eq("Net::SMTPFatalError" => 1, "Net::ReadTimeout" => 1)
  end
end
