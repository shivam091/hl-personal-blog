# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterEngagement do
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-10"}, today: Date.new(2026, 10, 12)) }
  let(:url) { "https://blog.example.com/post/a" }

  def event(name, email, message, link: nil)
    NewsletterEmailEvent.record("event" => name, "email" => email, "message-id" => message, "tags" => [url], "link" => link)
  end

  it "counts each reader once per kind of event for the entries sent in the period" do
    FeedEntry.create!(url: url, name: "A post", type: "post", published_at: Time.zone.parse("2026-10-02 08:00"),
      last_modified_at: Time.zone.parse("2026-10-02 08:00"), notified_at: Time.zone.parse("2026-10-02 09:00"), notified_count: 4)
    FeedEntry.create!(url: "https://blog.example.com/post/old", name: "Old", type: "post", published_at: Time.zone.parse("2026-09-02 08:00"),
      last_modified_at: Time.zone.parse("2026-09-02 08:00"), notified_at: Time.zone.parse("2026-09-02 09:00"), notified_count: 4)
    %w[a b c].each { |name| event("delivered", "#{name}@example.com", "<#{name}>") }
    event("hard_bounce", "d@example.com", "<d>")
    event("unique_opened", "a@example.com", "<a>")
    event("opened", "a@example.com", "<a>")
    event("opened", "b@example.com", "<b>")
    event("click", "a@example.com", "<a>", link: "https://blog.example.com/post/a")
    event("click", "a@example.com", "<a>", link: "https://blog.example.com/")

    row = described_class.new(period).rows.sole

    expect(row.to_h.except(:entry)).to eq(sent: 4, delivered: 3, opened: 2, clicked: 1, bounced: 1, unsubscribed: 0, spam: 0)
    expect(row.open_rate).to eq(2 / 3.0)
    expect(row.click_rate).to eq(1 / 3.0)
    expect(row.parts).to eq([1, 1, 1, 1])
  end

  it "counts a click whose open went unseen, and splits what was sent before deliveries are reported" do
    row = described_class::Row.new(sent: 5, delivered: 0, opened: 0, clicked: 1, bounced: 1)

    expect(row.parts).to eq([1, 0, 3, 1])
  end

  it "pools the period's mail into one open and click rate, nil without mail" do
    FeedEntry.create!(url: url, name: "A post", type: "post", published_at: Time.zone.parse("2026-10-02 08:00"),
      last_modified_at: Time.zone.parse("2026-10-02 08:00"), notified_at: Time.zone.parse("2026-10-02 09:00"), notified_count: 4)
    %w[a b c d].each { |name| event("delivered", "#{name}@example.com", "<#{name}>") }
    event("unique_opened", "a@example.com", "<a>")
    event("click", "a@example.com", "<a>", link: "https://blog.example.com/post/a")

    expect(described_class.new(period).rates).to eq(open_rate: 0.25, click_rate: 0.25)
    expect(described_class.new(Period.new({from: "2026-08-01", to: "2026-08-10"}, today: Date.new(2026, 10, 12))).rates).to be_nil
  end
end
