# encoding: UTF-8

require "rails_helper"

RSpec.describe PageLike, type: :model do
  let(:source_doc) do
    {
      "_id" => "/post/git/advanced-git-techniques-and-workflows",
      "slug" => "/post/git/advanced-git-techniques-and-workflows",
      "url" => "https://harshal-ladhe.vercel.app/post/git/advanced-git-techniques-and-workflows",
      "likeCount" => 1,
      "countriesByDay" => {"2026-08-23" => {"IN" => 1}},
      "createdAt" => Time.zone.parse("2026-08-23T07:00:42.538Z"),
      "updatedAt" => Time.zone.parse("2026-08-23T07:00:42.538Z")
    }
  end

  it "reads the frontend's camelCase fields through snake_case aliases" do
    PageLike.collection.insert_one(source_doc)
    like = PageLike.find(source_doc["_id"])

    expect(like.slug).to eq("/post/git/advanced-git-techniques-and-workflows")
    expect(like.url).to eq("https://harshal-ladhe.vercel.app/post/git/advanced-git-techniques-and-workflows")
    expect(like.like_count).to eq(1)
    expect(like.likes_by_day).to eq("2026-08-23" => 1)
    expect(like.countries_by_day).to eq("2026-08-23" => {"IN" => 1})
    expect(like.created_at).to eq(source_doc["createdAt"])
    expect(like.updated_at).to eq(source_doc["updatedAt"])
  end

  it "defaults breakdown hashes to empty when absent" do
    PageLike.collection.insert_one(source_doc.except("countriesByDay"))
    like = PageLike.first

    expect(like.likes_by_day).to eq({})
    expect(like.countries).to eq({})
    expect(like.countries_by_day).to eq({})
  end

  it "totals likes by day and by country from the dated breakdown" do
    PageLike.collection.insert_one(source_doc.merge(
      "countriesByDay" => {"2026-10-10" => {"IN" => 2, "US" => 1}, "2026-10-11" => {"IN" => 1}}
    ))
    like = PageLike.first

    expect(like.likes_by_day).to eq("2026-10-10" => 3, "2026-10-11" => 1)
    expect(like.countries).to eq("IN" => 3, "US" => 1)
  end

  it "is read-only" do
    PageLike.collection.insert_one(source_doc)
    like = PageLike.find(source_doc["_id"])

    like.like_count = 9
    expect { like.save! }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect { PageLike.new.save! }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect { like.destroy }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect(PageLike.collection.find(_id: source_doc["_id"]).first["likeCount"]).to eq(source_doc["likeCount"])
  end

  # The frontend owns this collection's indexes; db:mongoid:create_indexes
  # runs on every deploy and would add ours to its live collection.
  it "declares no indexes" do
    expect(described_class.index_specifications).to be_empty
  end
end
