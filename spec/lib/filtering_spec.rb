# encoding: UTF-8

require "rails_helper"

RSpec.describe Filtering do
  let(:fields) do
    [
      Filtering::Contains.new(:q, field: :url, label: "URL contains"),
      Filtering::DateRange.new(:modified, field: :last_modified_at, label: "Last modified")
    ]
  end
  let(:tabs) do
    Filtering::Tabs.new(:indexed, field: :indexed, label: "Indexed", choices: {"yes" => ["Indexed", true], "no" => ["Not indexed", false]})
  end

  def filtering(params = {})
    Filtering.new(params, fields: fields, tabs: tabs)
  end

  before do
    ListSpecDocument.collection.insert_many([
      {url: "https://example.com/css/a", indexed: true, last_modified_at: Time.utc(2026, 9, 1, 23)},
      {url: "https://example.com/css/b", indexed: false, last_modified_at: Time.utc(2026, 9, 3)},
      {url: "https://example.com/js/c", indexed: true, last_modified_at: Time.utc(2026, 9, 2)}
    ])
  end

  def urls(filtering)
    filtering.apply(ListSpecDocument.all).pluck(:url).sort
  end

  it "matches text literally and case-insensitively" do
    expect(urls(filtering(q: " CSS/ "))).to eq(%w[https://example.com/css/a https://example.com/css/b])
    expect(urls(filtering(q: "c.s"))).to be_empty
  end

  it "filters an inclusive date range, ignoring invalid dates" do
    expect(urls(filtering(modified_from: "2026-09-01", modified_to: "2026-09-02"))).to eq(%w[https://example.com/css/a https://example.com/js/c])
    expect(urls(filtering(modified_from: "garbage"))).to eq(urls(filtering))
  end

  it "filters by tab and counts tabs within the search" do
    css = filtering(q: "css", indexed: "yes")

    expect(urls(css)).to eq(%w[https://example.com/css/a])
    expect(css.tab_counts(ListSpecDocument.all)).to eq(nil => 2, "yes" => 1, "no" => 1)
    expect(filtering(indexed: "maybe").tab).to be_nil
  end

  it "describes active searches as chips and keeps them in link queries" do
    active = filtering(q: "css", modified_from: "2026-09-01", indexed: "no")

    expect(active.chips).to eq([["URL contains “css”", :q], ["Last modified from 1 Sep, 2026", :modified_from]])
    expect(active.query).to eq(q: "css", modified_from: "2026-09-01", indexed: "no")
    expect(active).to be_searching
    expect(filtering(indexed: "no")).to be_filtered.and(have_attributes(searching?: false))
  end

  it "reads a select's labelled choices by value, and shows them by label" do
    select = Filtering::Select.new(:indexed, field: :indexed, label: "Status", choices: {"yes" => "Indexed", "no" => "Not indexed"})

    expect(select.read({indexed: "no"})).to eq(indexed: "no")
    expect(select.read({indexed: "Not indexed"})).to eq(indexed: nil)
    expect(select.options).to eq([["Indexed", "yes"], ["Not indexed", "no"]])
    expect(select.chips(indexed: "no")).to eq([["Status: Not indexed", :indexed]])
  end
end
