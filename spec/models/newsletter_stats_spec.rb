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

  it "sums the period's sends by week, or by month over a long period, and groups what's still undelivered by error" do
    publish("/post/a", "2026-10-06 08:00", notified_at: Time.zone.parse("2026-10-06 09:00"), notified_count: 5,
      notification_failures: [{"email" => "x@example.com", "error" => "Net::SMTPFatalError: 550 no such user"},
        {"email" => "y@example.com", "error" => "Net::ReadTimeout: timed out"}])
    publish("/post/old", "2026-04-02 08:00", notified_at: Time.zone.parse("2026-04-02 09:00"), notified_count: 7)

    expect(stats.sends.map { |row| [row.start, row.sent, row.undelivered] }).to eq([[Date.new(2026, 9, 28), 0, 0], [Date.new(2026, 10, 5), 5, 2]])
    expect(stats.failure_reasons).to eq("Net::SMTPFatalError" => 1, "Net::ReadTimeout" => 1)

    year = described_class.new(Period.new({from: "2025-10-12", to: "2026-10-11"}, today: today), today: today)
    expect(year.sends_by).to eq(:month)
    expect(year.sends.size).to eq(13)
    expect(year.sends.find { |row| row.start == Date.new(2026, 4, 1) }.sent).to eq(7)
  end

  it "narrows the list and sign-ups to a country, counting subscribers with none as Unknown" do
    NewsletterSubscriber.create!(email: "in@example.com", country: "in", subscribed_at: Time.zone.parse("2026-10-05 10:00"))
    NewsletterSubscriber.create!(email: "us@example.com", country: "US", subscribed_at: Time.zone.parse("2026-10-05 10:00"))
    subscribe("2026-10-06 10:00")

    expect(described_class.new(period, country: "IN", today: today).new_subscribers).to eq(1)
    expect(described_class.new(period, country: BlogStats::UNKNOWN_COUNTRY, today: today).list_size).to eq(1)
    compared = Period.new({from: "2026-10-01", to: "2026-10-11", compare: "country", vs: "US"}, today: today, countries: true)
    expect(described_class.new(compared, country: "IN", today: today).new_subscribers(compared.previous)).to eq(1)
  end

  it "exports each entry's sign-ups and the period's sends as CSV" do
    publish("/post/a", "2026-10-02 08:00", notified_at: Time.zone.parse("2026-10-02 09:00"), notified_count: 3)
    subscribe("2026-10-03 10:00")

    expect(CSV.parse(stats.to_csv("entries"))).to eq([
      ["URL", "Title", "Published", "Sign-ups week before", "Sign-ups week after", "Change", "Week after complete"],
      ["https://blog.example.com/post/a", "/post/a", "2026-10-02", "0", "1", "1", "Yes"]
    ])
    expect(CSV.parse(stats.to_csv("sends"))).to eq([["Week starting", "Sent", "Undelivered"], ["2026-09-28", "3", "0"], ["2026-10-05", "0", "0"]])
  end
end
