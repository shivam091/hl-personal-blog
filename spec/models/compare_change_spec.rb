require "rails_helper"

RSpec.describe CompareChange do
  describe ".label" do
    it "words a rise, a fall, nothing before and no change" do
      expect(described_class.label(103, 100)).to eq("(+3%)")
      expect(described_class.label(97, 100)).to eq("(−3%)")
      expect(described_class.label(5, 0)).to eq("(new)")
      expect(described_class.label(0, 0)).to eq("(–)")
      expect(described_class.label(7, 7)).to eq("(0%)")
    end
  end

  describe ".cell" do
    it "puts the change in brackets after the figure, with a plain minus" do
      expect(described_class.cell(1, 1)).to eq("1 (0%)")
      expect(described_class.cell(97, 100)).to eq("97 (-3%)")
      expect(described_class.cell(3, nil)).to eq("3 (new)")
    end

    it "leaves the figure alone when nothing is compared" do
      expect(described_class.cell(97, 100, compare: false)).to eq(97)
      expect(described_class.cell(nil, 100)).to be_nil
    end
  end
end
