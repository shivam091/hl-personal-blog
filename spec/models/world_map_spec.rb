# encoding: UTF-8

require "rails_helper"

RSpec.describe WorldMap do
  it "has an outline for each country under its ISO code" do
    expect(described_class.codes).to include("IN", "US", "GB", "DE")
    expect(described_class.countries.find { |country| country.code == "IN" }.name).to eq("India")
    expect(described_class.countries.map(&:path)).to all(start_with("M"))
  end

  # Natural Earth gives these "-99" as their main code, so they'd be lost
  # without its fallback one.
  it "keeps France and Norway under their real codes" do
    expect(described_class.codes).to include("FR", "NO")
  end

  it "leaves out Antarctica, where nobody reads from" do
    expect(described_class.codes).not_to include("AQ")
  end

  it "fits every shape inside the drawing" do
    numbers = described_class.countries.flat_map { |country| country.path.scan(/-?\d+(?:\.\d+)?/).map(&:to_f) }

    expect(numbers.min).to be >= 0
    expect(numbers.max).to be <= described_class.width
  end
end
