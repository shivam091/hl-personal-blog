# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterUnsubscribe do
  def unsubscribe(**fields)
    described_class.collection.insert_one({"email" => "reader@example.com"}.merge(fields.stringify_keys))
    described_class.last
  end

  it "reads the blog's camelCase fields, the method under a name that doesn't hide Object#method" do
    record = unsubscribe(subscribedAt: Time.utc(2026, 9, 1), unsubscribedAt: Time.utc(2026, 9, 11, 12), method: "one_click", sourcePage: "/post/a")

    expect(record.unsubscribe_method).to eq("one_click")
    expect(record.method_label).to eq("One-click, from the mail app")
    expect(record.method(:email)).to be_a(Method)
    expect(record.source_page).to eq("/post/a")
    expect(record.days_subscribed).to eq(10)
  end

  it "has no stay when the subscriber record held no sign-up time" do
    expect(unsubscribe(unsubscribedAt: Time.utc(2026, 9, 11)).days_subscribed).to be_nil
  end

  it "can't be saved, as the blog owns the collection" do
    expect(unsubscribe(method: "link")).to be_readonly
  end

  # The frontend owns this collection's indexes; db:mongoid:create_indexes
  # runs on every deploy and would add ours to its live collection.
  it "declares no indexes" do
    expect(described_class.index_specifications).to be_empty
  end
end
