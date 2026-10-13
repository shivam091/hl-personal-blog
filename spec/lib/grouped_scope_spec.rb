# encoding: UTF-8

require "rails_helper"

RSpec.describe GroupedScope do
  let(:row_class) do
    Class.new(GroupedScope::Row) do
      def clicks
        self[:clicks].to_i
      end
    end
  end

  before do
    ListSpecDocument.collection.insert_many([
      {url: "a", indexed: true, clicks: 3},
      {url: "a", indexed: true, clicks: 4},
      {url: "b", indexed: false, clicks: 5},
      {url: "c", indexed: false, clicks: 1}
    ])
  end

  def grouped(criteria = ListSpecDocument.all)
    described_class.new(criteria, keys: [:url], sums: {clicks: "$clicks", rows: 1},
      derived: {"per_row" => {"$divide" => ["$clicks", "$rows"]}}, row_class: row_class)
  end

  it "sums each group, works out derived figures, and sorts, skips and limits like a criteria" do
    rows = grouped.order("clicks" => "desc", "url" => "asc").skip(1).limit(2).to_a

    expect(rows.map { |row| [row[:url], row.clicks, row.value(:per_row)] }).to eq([["b", 5, 5.0], ["c", 1, 1.0]])
  end

  it "counts groups rather than rows" do
    expect(grouped.count).to eq(3)
    expect(grouped(ListSpecDocument.where(indexed: true)).count).to eq(1)
  end

  it "totals every group, even an empty selection" do
    expect(grouped.totals.clicks).to eq(13)
    expect(grouped(ListSpecDocument.where(url: "none")).totals.clicks).to eq(0)
  end

  it "pages through Sorting and Pagination like any list" do
    sorting = Sorting.new({sort: "clicks", direction: "desc"}, columns: {"clicks" => "desc"}, tiebreaker: :url)
    pagination = Pagination.new(sorting.apply(grouped), {page: 2}, per_page_options: [2])

    expect(pagination.total_count).to eq(3)
    expect(pagination.records.map { |row| row[:url] }).to eq(["c"])
  end

  it "exports the listed rows as CSV" do
    expect(grouped.order("url" => "asc").to_csv("URL" => :url, "Clicks" => :clicks)).to eq("URL,Clicks\na,7\nb,5\nc,1\n")
  end
end
