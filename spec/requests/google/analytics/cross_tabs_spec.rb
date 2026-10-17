# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics cross-tab", type: :request do
  let(:service) { Google::Analytics::PivotService }
  let(:table) do
    service::Table.new(rows: ["Organic Search", "Direct"], columns: %w[IN US],
      cells: {["Organic Search", "IN"] => 30, ["Organic Search", "US"] => 12, ["Direct", "US"] => 5},
      row_totals: {"Organic Search" => 40, "Direct" => 5}, column_totals: {"IN" => 30, "US" => 16}, total: 44)
  end

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    allow(service).to receive(:call) do |_period, rows:, columns:, metric:|
      service::Result.new(table: table, rows: rows || "channel", columns: columns || "country", metric: metric || "readers", errors: [])
    end
  end

  it "lays the picks out as a grid with each row's and column's total" do
    get google_analytics_cross_tab_path(rows: "channel", columns: "country", metric: "readers")

    expect(service).to have_received(:call).with(anything, rows: "channel", columns: "country", metric: "readers")
    grid = page.at_css("#cross-tab ~ div table")
    headings = grid.css("thead th").map { |th| th.text.strip }
    expect([headings.first, headings.last]).to eq(%w[Channel Total])
    expect(headings.second).to include("IN")
    expect(grid.css("tbody tr").map { |row| row.css("td").map { |td| td.text.strip } }).to eq([%w[30 12 40], %w[0 5 5]])
    expect(grid.css("tfoot td").map { |td| td.text.strip }).to eq(%w[30 16 44])
    expect(page.css("#cross-tab-columns option").map { |option| option["value"] }).not_to include("channel")
  end

  it "exports the grid as CSV" do
    get google_analytics_cross_tab_path(format: :csv, rows: "channel", columns: "country", metric: "readers")

    expect(CSV.parse(response.body).last).to eq(%w[Total 30 16 44])
  end
end
