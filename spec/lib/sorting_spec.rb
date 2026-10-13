# encoding: UTF-8

require "rails_helper"

RSpec.describe Sorting do
  let(:columns) { {"url" => "asc", "last_modified_at" => "desc"} }

  def sorting(params = {})
    Sorting.new(params, columns: columns, tiebreaker: :url)
  end

  it "defaults to the first column in its initial direction" do
    expect([sorting.column, sorting.direction]).to eq(["url", "asc"])
    expect(sorting.query).to eq({})
  end

  it "only accepts whitelisted columns and directions" do
    expect([sorting(sort: "$where", direction: "up").column]).to eq(["url"])
    expect([sorting(sort: "$where", direction: "up").direction]).to eq(["asc"])
    expect(sorting(sort: "last_modified_at").direction).to eq("desc")
  end

  it "flips the direction for the current column and starts others in their initial direction" do
    current = sorting(sort: "last_modified_at", direction: "desc")

    expect(current.toggle_query("last_modified_at")).to eq(sort: "last_modified_at", direction: "asc")
    expect(current.toggle_query("url")).to eq(sort: "url", direction: "asc")
    expect(current.query).to eq(sort: "last_modified_at", direction: "desc")
    expect(current.aria_sort("last_modified_at")).to eq("descending")
    expect(current.aria_sort("url")).to eq("none")
  end

  it "orders by the column, then the tiebreaker" do
    ListSpecDocument.collection.insert_many([
      {url: "https://example.com/b", last_modified_at: Time.utc(2026, 9, 1)},
      {url: "https://example.com/a", last_modified_at: Time.utc(2026, 9, 1)},
      {url: "https://example.com/c", last_modified_at: Time.utc(2026, 9, 2)}
    ])

    urls = sorting(sort: "last_modified_at", direction: "desc").apply(ListSpecDocument.all).pluck(:url)
    expect(urls).to eq(%w[https://example.com/c https://example.com/a https://example.com/b])
    expect(sorting(sort: "url", direction: "desc").apply(ListSpecDocument.all).pluck(:url).first).to eq("https://example.com/c")
  end
end
