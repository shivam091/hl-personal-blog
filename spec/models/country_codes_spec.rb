# encoding: UTF-8

require "rails_helper"

RSpec.describe CountryCodes do
  it "matches Search Console's alpha-3 codes, in any case, to alpha-2" do
    expect(described_class.from_iso3("ind")).to eq("IN")
    expect(described_class.from_iso3("NOR")).to eq("NO")
    expect(described_class.from_iso3("XXX")).to be_nil
  end

  it "matches the names Google gives countries to alpha-2" do
    expect(described_class.from_name(" India ")).to eq("IN")
    expect(described_class.from_name("Ivory Coast")).to eq("CI")
    expect(described_class.from_name("Côte d'Ivoire")).to eq("CI")
    expect(described_class.from_name("Atlantis")).to be_nil
  end
end
