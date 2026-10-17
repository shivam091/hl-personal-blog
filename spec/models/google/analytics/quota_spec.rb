# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::Quota do
  let(:response) do
    {
      "rows" => [],
      "propertyQuota" => {
        "tokensPerDay" => {"consumed" => 12, "remaining" => 15_000},
        "tokensPerHour" => {"consumed" => 12, "remaining" => 39_000},
        "concurrentRequests" => {"consumed" => 0, "remaining" => 10},
        "unknownQuota" => {"remaining" => 1}
      }
    }
  end

  it "keeps the latest quota per kind of request, replacing the one before" do
    described_class.record("core", response)
    described_class.record("core", response.deep_merge("propertyQuota" => {
      "tokensPerDay" => {"consumed" => 5, "remaining" => 14_995}
    }))

    quota = described_class.all.sole

    expect(quota.category).to eq("core")
    expect(quota.quota.keys).to contain_exactly("tokensPerDay", "tokensPerHour", "concurrentRequests")

    day = quota.usages.find { |usage| usage.key == "tokensPerDay" }

    expect(day.to_h).to include(consumed: 5, remaining: 14_995, limit: 200_000)
    expect(day).to be_low
    expect(quota).to be_low
  end

  it "ignores a response without quota" do
    described_class.record("core", {"rows" => []})

    expect(described_class.count).to eq(0)
  end
end
