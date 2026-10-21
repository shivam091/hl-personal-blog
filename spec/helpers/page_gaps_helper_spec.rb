# encoding: UTF-8

require "rails_helper"

RSpec.describe PageGapsHelper, type: :helper do
  describe "#log_ticks" do
    it "marks round figures from the least views judged to the first at or over the most" do
      expect(helper.log_ticks(20, 91)).to eq([20, 50, 100])
      expect(helper.log_ticks(20, 20)).to eq([20, 50])
    end

    it "keeps to powers of ten when every step would crowd the axis" do
      expect(helper.log_ticks(20, 40_000)).to eq([20, 100, 1_000, 10_000, 50_000])
    end
  end
end
