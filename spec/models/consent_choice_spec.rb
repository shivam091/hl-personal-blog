# encoding: UTF-8

require "rails_helper"

RSpec.describe ConsentChoice, type: :model do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-11"}) }

  before do
    ConsentChoice.collection.insert_many([
      {"_id" => "2026-10-09", "day" => "2026-10-09", "countries" => {"GB" => {"shown" => 1}}},
      {"_id" => "2026-10-10", "day" => "2026-10-10", "countries" => {"GB" => {"shown" => 4, "granted" => 2, "denied" => 1}},
       "createdAt" => Time.zone.parse("2026-10-10T08:00:00Z")},
      {"_id" => "2026-10-12", "day" => "2026-10-12", "countries" => {}}
    ])
  end

  it "reads the frontend's camelCase fields through snake_case aliases" do
    choice = ConsentChoice.find("2026-10-10")

    expect(choice.day).to eq("2026-10-10")
    expect(choice.countries).to eq("GB" => {"shown" => 4, "granted" => 2, "denied" => 1})
    expect(choice.created_at).to eq(Time.zone.parse("2026-10-10T08:00:00Z"))
  end

  it "selects the days of a period, ends included" do
    expect(ConsentChoice.within(period).map(&:day)).to eq(["2026-10-10"])
  end

  it "finds the first day recorded, and none when there isn't one" do
    expect(ConsentChoice.first_day).to eq(Date.new(2026, 10, 9))

    ConsentChoice.collection.delete_many({})
    expect(ConsentChoice.first_day).to be_nil
  end

  it "is read-only" do
    expect(ConsentChoice.new).to be_readonly
  end
end
