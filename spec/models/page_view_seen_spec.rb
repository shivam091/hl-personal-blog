# encoding: UTF-8

require "rails_helper"

RSpec.describe PageViewSeen, type: :model do
  # Shaped like the frontend writes it, so the camelCase aliases are tested
  # against real data.
  let(:source_doc) do
    {
      "_id" => BSON::ObjectId.new,
      "slug" => "/post/git/advanced-git-techniques-and-workflows",
      "day" => "2026-08-23",
      "ipHash" => "5f4b2db16e9476646b2b26bf3e382b0a",
      "country" => "IN",
      "at" => Time.zone.parse("2026-08-23T06:59:21.224Z")
    }
  end

  it "reads the frontend's camelCase fields through snake_case aliases" do
    PageViewSeen.collection.insert_one(source_doc)
    seen = PageViewSeen.find(source_doc["_id"])

    expect(seen.slug).to eq("/post/git/advanced-git-techniques-and-workflows")
    expect(seen.day).to eq("2026-08-23")
    expect(seen.ip_hash).to eq("5f4b2db16e9476646b2b26bf3e382b0a")
    expect(seen.country).to eq("IN")
    expect(seen.seen_at).to eq(source_doc["at"])
  end

  it "saves in the frontend's camelCase field names" do
    seen = PageViewSeen.create!(slug: "/post/a", day: "2026-08-23", ip_hash: "abc", seen_at: Time.zone.parse("2026-08-23T06:59:21Z"))

    stored = PageViewSeen.collection.find(_id: seen.id).first
    expect(stored.except("_id")).to eq({"slug" => "/post/a", "day" => "2026-08-23", "ipHash" => "abc", "at" => Time.zone.parse("2026-08-23T06:59:21Z")})
  end

  it "requires a slug" do
    seen = PageViewSeen.new
    expect(seen).not_to be_valid
    expect(seen.errors[:slug]).to be_present
  end

  # The frontend owns this collection's indexes; db:mongoid:create_indexes
  # runs on every deploy and would add ours to its live collection.
  it "declares no indexes" do
    expect(described_class.index_specifications).to be_empty
  end
end
