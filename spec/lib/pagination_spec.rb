# encoding: UTF-8

require "rails_helper"

RSpec.describe Pagination do
  before do
    ListSpecDocument.collection.insert_many((1..45).map do |n|
      {url: format("https://example.com/%02d", n), indexed: false}
    end)
  end

  let(:scope) { ListSpecDocument.order(url: :asc) }

  it "fetches only the requested page" do
    pagination = Pagination.new(scope, {page: "2"}, per_page_options: [20])

    expect(pagination.records.map(&:url)).to eq((21..40).map { |n| "https://example.com/#{n}" })
    expect([pagination.first_item, pagination.last_item, pagination.total_count]).to eq([21, 40, 45])
    expect([pagination.previous_page, pagination.next_page, pagination.total_pages]).to eq([1, 3, 3])
  end

  it "clamps out-of-range and junk page numbers" do
    expect(Pagination.new(scope, {page: "99"}, per_page_options: [20]).page).to eq(3)
    expect(Pagination.new(scope, {page: "abc"}, per_page_options: [20]).page).to eq(1)
    expect(Pagination.new(ListSpecDocument.none, {page: "2"}, per_page_options: [20]).page).to eq(1)
  end

  it "starts from a given default page size, leaving it out of URLs" do
    pagination = Pagination.new(scope, {}, per_page_options: [25, 50], default_per_page: 50)

    expect(pagination.per_page).to eq(50)
    expect(pagination.query).to eq({})
    expect(pagination.per_page_query(25)).to eq(per_page: 25)
    expect(Pagination.new(scope, {}, per_page_options: [25, 50], default_per_page: 7).per_page).to eq(25)
  end

  it "reads the page size from params, falling back to the first option" do
    expect(Pagination.new(scope, {per_page: "50"}, per_page_options: [25, 50]).per_page).to eq(50)
    expect(Pagination.new(scope, {per_page: "7"}, per_page_options: [25, 50]).per_page).to eq(25)
  end

  it "keeps a non-default page size in link queries, and the page only in page links" do
    pagination = Pagination.new(scope, {per_page: "50"}, per_page_options: [25, 50])

    expect(pagination.query).to eq(per_page: 50)
    expect(pagination.page_query(1)).to eq(per_page: 50)
    expect(pagination.page_query(2)).to eq(per_page: 50, page: 2)
    expect(pagination.per_page_query(25)).to eq({})
  end

  it "windows page links around the current page, marking gaps with nil" do
    pagination = Pagination.new(scope, {page: "5"}, per_page_options: [4])

    expect(pagination.window).to eq([1, nil, 3, 4, 5, 6, 7, nil, 12])
    expect(Pagination.new(scope, {page: "1"}, per_page_options: [4]).window).to eq([1, 2, 3, nil, 12])
  end
end
