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

    expect(service).to have_received(:call).with(anything, rows: "channel", columns: "country", metric: "readers").at_least(:once)
    grid = page.at_css("#cross-tab ~ div table")
    headings = grid.css("thead th").map { |th| th.text.strip }
    expect([headings.first, headings.last]).to eq(%w[Channel Total])
    expect(headings.second).to include("IN")
    expect(grid.css("tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }).to eq([["30", "12", "40 (0%)"], ["0", "5", "5 (0%)"]])
    expect(grid.css("tfoot td").map { |td| td.text.squish }).to eq(["30 (0%)", "16 (0%)", "44 (0%)"])
    expect(page.css("#cross-tab-columns option").map { |option| option["value"] }).not_to include("channel")
  end

  it "exports the grid as CSV" do
    get google_analytics_cross_tab_path(format: :csv, rows: "channel", columns: "country", metric: "readers")

    expect(CSV.parse(response.body).last).to eq(["Total", "30 (0%)", "16 (0%)", "44 (0%)"])
  end

  context "with a different period before" do
    let(:earlier) do
      service::Table.new(rows: ["Organic Search", "Direct"], columns: %w[IN US],
        cells: {["Organic Search", "IN"] => 10, ["Direct", "US"] => 10},
        row_totals: {"Organic Search" => 20, "Direct" => 10}, column_totals: {"IN" => 10, "US" => 10}, total: 22)
    end

    before do
      allow(service).to receive(:call) do |period, rows:, columns:, metric:|
        service::Result.new(table: (period.from == Date.current - 28) ? table : earlier, rows: rows || "channel", columns: columns || "country",
          metric: metric || "readers", errors: [])
      end
    end

    it "shows each total's change and leaves it out when comparison is off" do
      get google_analytics_cross_tab_path
      grid = page.at_css("#cross-tab ~ div table")

      expect(grid.css("tbody tr").map { |row| row.css("td").last.text.squish }).to eq(["40 (+100%)", "5 (−50%)"])
      expect(grid.css("tfoot td").map { |td| td.text.squish }).to eq(["30 (+200%)", "16 (+60%)", "44 (+100%)"])

      get google_analytics_cross_tab_path(compare: "off")

      expect(page.at_css("#cross-tab ~ div table").css("tfoot td").map { |td| td.text.squish }).to eq(%w[30 16 44])
    end

    it "puts the changes in the CSV" do
      get google_analytics_cross_tab_path(format: :csv)

      expect(CSV.parse(response.body)[1]).to eq(["Organic Search", "30 (+200%)", "12 (new)", "40 (+100%)"])
    end
  end
end
