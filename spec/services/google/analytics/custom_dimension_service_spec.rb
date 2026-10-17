# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::CustomDimensionService do
  let(:url) { "https://analyticsadmin.googleapis.com/v1beta/properties/123456789/customDimensions" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  def register(**options)
    described_class.call("event_label", property: 123456789, client: google_client, cache: cache, **options)
  end

  it "registers the parameter as an event-scoped dimension and forgets the cached settings" do
    cache.write(Google::Analytics::SettingsService.cache_key("123456789"), :stale)
    sent = []
    google_stubs.post(url) do |env|
      sent << JSON.parse(env.body)
      [200, {}, {name: "properties/123456789/customDimensions/1"}.to_json]
    end

    expect(register.summary).to eq("1 created, 0 updated, 0 unchanged, 0 failed")
    expect(sent).to eq([{"parameterName" => "event_label", "displayName" => "Event label", "scope" => "EVENT"}])
    expect(cache.read(Google::Analytics::SettingsService.cache_key("123456789"))).to be_nil
  end

  it "registers read_seconds as an event-scoped metric counted in seconds" do
    sent = []
    google_stubs.post("https://analyticsadmin.googleapis.com/v1beta/properties/123456789/customMetrics") do |env|
      sent << JSON.parse(env.body)
      [200, {}, {name: "properties/123456789/customMetrics/1"}.to_json]
    end

    result = described_class.call("read_seconds", property: 123456789, client: google_client, cache: cache)

    expect(result.errors).to eq([])
    expect(sent).to eq([{"parameterName" => "read_seconds", "displayName" => "Read seconds", "scope" => "EVENT", "measurementUnit" => "SECONDS"}])
  end

  it "reports GA's refusal, such as a Viewer-only service account" do
    google_stubs.post(url) { [403, {}, {error: {message: "The caller does not have permission"}}.to_json] }

    expect(register.errors).to eq(["Custom dimension event_label: The caller does not have permission"])
  end
end
