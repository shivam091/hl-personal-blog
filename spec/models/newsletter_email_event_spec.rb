# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterEmailEvent do
  def payload(**overrides)
    {"event" => "click", "email" => "Reader@Example.com", "message-id" => "<abc@smtp-relay.mailin.fr>", "tags" => ["https://blog.example.com/post/a"],
     "link" => "https://blog.example.com/post/a?utm_content=button", "ts_epoch" => 1_790_000_000_123}.merge(overrides)
  end

  it "stores an event Brevo posts, with the entry it was tagged with" do
    described_class.record(payload)

    event = described_class.all.sole
    expect(event.attributes.slice("event", "email", "message_id", "tag", "link"))
      .to eq("event" => "click", "email" => "reader@example.com", "message_id" => "<abc@smtp-relay.mailin.fr>",
        "tag" => "https://blog.example.com/post/a", "link" => "https://blog.example.com/post/a?utm_content=button")
    expect(event.occurred_at).to eq(Time.zone.at(1_790_000_000, 123, :millisecond))
    expect(event.attributes).not_to include("created_at", "updated_at")
  end

  it "stores a retried event once, but a click on another link as its own" do
    2.times { described_class.record(payload) }
    described_class.record(payload("link" => "https://blog.example.com/"))
    described_class.record(payload("event" => "delivered", "link" => nil, "tags" => nil, "tag" => "https://blog.example.com/post/a"))

    expect(described_class.count).to eq(3)
    expect(described_class.where(event: "delivered").to_a.sole.tag).to eq("https://blog.example.com/post/a")
  end

  it "leaves out events that say nothing of a reader, or can't be told apart" do
    described_class.record(payload("event" => "request"))
    described_class.record(payload("message-id" => nil))

    expect(described_class.count).to eq(0)
  end
end
