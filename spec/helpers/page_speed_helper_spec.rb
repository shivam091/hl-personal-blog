# encoding: UTF-8

require "rails_helper"

RSpec.describe PageSpeedHelper, type: :helper do
  it "colours a score by Lighthouse's bands" do
    expect(helper.lighthouse_score_class(0.9)).to eq("text-emerald-700")
    expect(helper.lighthouse_score_class(0.89)).to eq("text-amber-700")
    expect(helper.lighthouse_score_class(0.5)).to eq("text-amber-700")
    expect(helper.lighthouse_score_class(0.49)).to eq("font-medium text-red-700")
    expect(helper.lighthouse_score_class(nil)).to eq("text-slate-400")
  end

  it "fills a cell by the same bands" do
    expect(helper.lighthouse_cell_class(0.95)).to eq("bg-emerald-100 text-emerald-800")
    expect(helper.lighthouse_cell_class(0.6)).to eq("bg-amber-100 text-amber-800")
    expect(helper.lighthouse_cell_class(0.2)).to eq("bg-red-100 font-medium text-red-800")
    expect(helper.lighthouse_cell_class(nil)).to eq("bg-slate-50 text-slate-400")
  end

  it "names CrUX's overall verdict in the colours of its ratings" do
    expect(helper.field_category_label("SLOW")).to eq('<span class="font-medium text-red-700">Slow</span>')
    expect(helper.field_category_label("FAST")).to eq('<span class="text-emerald-700">Fast</span>')
    expect(helper.field_category_label(nil)).to include("—")
  end

  it "writes each lab figure in PageSpeed Insights' units" do
    expect(helper.lab_value(:lab_fcp_ms, 1234)).to eq("1.2 s")
    expect(helper.lab_value(:lab_tbt_ms, 1234.4)).to eq("1,234 ms")
    expect(helper.lab_value(:lab_cls, 0.1)).to eq("0.1")
    expect(helper.lab_value(:lab_speed_index_ms, nil)).to eq("—")
  end
end
