# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterSubscriber, type: :model do
  # Shaped like the frontend writes it, so the camelCase aliases are tested
  # against real data.
  let(:source_doc) do
    {
      "_id" => BSON::ObjectId.new,
      "email" => "subscriber@domain.com",
      "country" => "IN",
      "subscribedAt" => Time.zone.parse("2026-08-23T07:00:25.074Z")
    }
  end

  it "reads the frontend's camelCase fields through snake_case aliases" do
    NewsletterSubscriber.collection.insert_one(source_doc)
    subscriber = NewsletterSubscriber.find(source_doc["_id"])

    expect(subscriber.email).to eq("subscriber@domain.com")
    expect(subscriber.country).to eq("IN")
    expect(subscriber.subscribed_at).to eq(source_doc["subscribedAt"])
  end

  it "saves in the frontend's camelCase field names" do
    subscriber = NewsletterSubscriber.create!(email: "new@domain.com", subscribed_at: Time.zone.parse("2026-08-23T07:00:25Z"))

    stored = NewsletterSubscriber.collection.find(_id: subscriber.id).first
    expect(stored.except("_id")).to eq({"email" => "new@domain.com", "subscribedAt" => Time.zone.parse("2026-08-23T07:00:25Z")})
  end

  it "requires a email" do
    subscriber = NewsletterSubscriber.new
    expect(subscriber).not_to be_valid
    expect(subscriber.errors[:email]).to be_present
  end

  # The frontend owns this collection's indexes; db:mongoid:create_indexes
  # runs on every deploy and would add ours to its live collection.
  it "declares no indexes" do
    expect(described_class.index_specifications).to be_empty
  end

  describe "unsubscribe tokens" do
    before do
      allow(Rails.application.credentials).to receive(:dig).and_call_original
      allow(Rails.application.credentials).to receive(:dig).with(:mailer, :unsubscribe_secret) { "test-secret" }
    end

    # Known answer, computed with openssl. The frontend checks these tokens
    # on its /unsubscribe page, and its unsubscribeSignature gives the same
    # one, so a change here breaks every link there.
    it "signs the id with HMAC-SHA256, as the frontend does" do
      subscriber = NewsletterSubscriber.new(id: BSON::ObjectId.from_string("6ad31427c50919df4939bdb8"))

      expect(subscriber.unsubscribe_token).to eq("6ad31427c50919df4939bdb8.4c1f4fec86e48af78ce324ee635502d84676151dd50e85b3ecf93dbef7e3e24b")
    end
  end
end
