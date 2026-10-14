# encoding: UTF-8

require "rails_helper"

RSpec.describe Message, type: :model do
  # Shaped like the frontend writes it, so the camelCase aliases are tested
  # against real data.
  let(:source_doc) do
    {
      "_id" => BSON::ObjectId.new,
      "name" => "Ada Lovelace",
      "email" => "ada@domain.com",
      "message" => "Loved the CSS grid post.",
      "recaptchaScore" => 0.9,
      "country" => "IN",
      "createdAt" => Time.zone.parse("2026-09-01T10:00:00Z")
    }
  end

  it "reads the collection the frontend writes contact-form messages to" do
    expect(Message.collection.name).to eq("messages")
  end

  it "reads the frontend's camelCase fields through snake_case aliases" do
    Message.collection.insert_one(source_doc)
    message = Message.find(source_doc["_id"])

    expect(message).to have_attributes(name: "Ada Lovelace", email: "ada@domain.com", message: "Loved the CSS grid post.",
      recaptcha_score: 0.9, country: "IN", created_at: source_doc["createdAt"])
    expect(message.to_s).to eq("Ada Lovelace <ada@domain.com>")
  end

  it "is read-only" do
    Message.collection.insert_one(source_doc)
    message = Message.find(source_doc["_id"])

    message.name = "Someone else"
    expect { message.save! }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect { message.destroy }.to raise_error(Mongoid::Errors::ReadonlyDocument)
  end

  # The frontend owns this collection's indexes; db:mongoid:create_indexes
  # runs on every deploy and would add ours to its live collection.
  it "declares no indexes" do
    expect(described_class.index_specifications).to be_empty
  end
end
