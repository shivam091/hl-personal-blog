# encoding: UTF-8

require "rails_helper"

RSpec.describe CompareChartsHelper, type: :helper do
  before { helper.extend(CompareHelper, GoogleReportsHelper) }

  def period(compare = nil)
    Period.new({from: "2026-10-01", to: "2026-10-07", compare: compare}.compact, today: Date.new(2026, 10, 12))
  end

  it "reads each slice against the same slice in the period before, folding what the donut folds into Other" do
    assign(:period, period)
    html = helper.donut_comparison({"mobile" => 6, "desktop" => 4}, {"mobile" => 2, "desktop" => 4, "tablet" => 2}, unit: "view", previous_name: "earlier")
    text = Nokogiri::HTML5.fragment(html).text.squish

    expect(text).to include("Against earlier")
    expect(text).to include("2 views · 25.0%", "(+200%)")
    expect(text).to include("4 views · 50.0%", "(0%)")
  end

  it "draws a second dashed line only when there is a period before" do
    points = [[Date.new(2026, 10, 1), 3], [Date.new(2026, 10, 2), 5]]
    plain = helper.compared_time_chart(points, previous: nil, previous_name: "earlier", label: "Likes", y_title: "Likes")
    compared = helper.compared_time_chart(points, previous: [1, 2], previous_name: "earlier", label: "Likes", y_title: "Likes")

    expect(plain).not_to include("against earlier")
    expect(compared).to include("against earlier")
  end

  it "puts the earlier count beside a cell's own, with the change under the current one" do
    expect(helper.cell_readings("Views", 6, 3, "earlier")).to eq([
      {name: "Views", value: "6", change: "(+100%)", tone: 1}, {name: "Views", period: "earlier", value: "3", dotted: true, earlier: true}
    ])
    expect(helper.cell_readings("Views", 6, nil, "earlier")).to eq([{value: "6", name: "Views"}])
  end
end
