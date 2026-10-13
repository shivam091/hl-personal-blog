# encoding: UTF-8

require "rails_helper"

RSpec.describe IpInfoService do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) do
    Faraday.new { |faraday| faraday.response :raise_error; faraday.adapter :test, stubs }
  end
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }

  def service(endpoints: ["https://ipinfo.io/%{ip}/json", "https://api.ipinfo.io/lite/%{ip}"])
    described_class.new(token: "token", endpoints: endpoints, cache: cache, connection: connection)
  end

  it "merges what each endpoint knows about the IP" do
    stubs.get("https://ipinfo.io/8.8.8.8/json") { [200, {}, {ip: "8.8.8.8", city: "Mountain View", country: "US"}.to_json] }
    stubs.get("https://api.ipinfo.io/lite/8.8.8.8") { [200, {}, {asn: "AS15169", country: "United States", country_code: "US"}.to_json] }

    expect(service.lookup("8.8.8.8")).to eq(
      "ip" => "8.8.8.8", "city" => "Mountain View", "asn" => "AS15169", "country" => "United States", "country_code" => "US"
    )
  end

  it "caches lookups per IP" do
    calls = 0
    stubs.get("https://ipinfo.io/8.8.8.8/json") { calls += 1; [200, {}, "{}"] }

    2.times { service(endpoints: ["https://ipinfo.io/%{ip}/json"]).lookup("8.8.8.8") }

    expect(calls).to eq(1)
  end

  it "skips addresses the API can't know about" do
    %w[127.0.0.1 10.0.0.5 192.168.1.1 ::1 not-an-ip].each do |ip|
      expect(service.lookup(ip)).to be_nil
    end
  end

  it "records a failure instead of raising" do
    stubs.get("https://ipinfo.io/8.8.8.8/json") { [403, {}, '{"error":"no access"}'] }

    expect(service(endpoints: ["https://ipinfo.io/%{ip}/json"]).lookup("8.8.8.8")).to include("ip" => "8.8.8.8", "error" => be_present)
  end

  it "does nothing without a token" do
    expect(described_class.new(token: nil, endpoints: ["x"], cache: cache).lookup("8.8.8.8")).to be_nil
  end
end
