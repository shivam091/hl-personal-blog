# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::KeyClient do
  let(:url) { "https://example.googleapis.com/v1/report" }

  it "tries once more when the connection doesn't open" do
    attempts = 0
    google_stubs.get(url) do
      attempts += 1
      raise Faraday::ConnectionFailed, "Failed to open TCP connection" if attempts == 1
      [200, {}, {rows: []}.to_json]
    end
    client = google_key_client
    allow(client).to receive(:sleep)

    expect(client.get(url)).to eq("rows" => [])
    expect(attempts).to eq(2)
  end

  it "gives up after the second failed connection" do
    attempts = 0
    google_stubs.post(url) { attempts += 1; raise Faraday::ConnectionFailed, "Failed to open TCP connection" }
    client = google_key_client
    allow(client).to receive(:sleep)

    expect { client.post(url, {}) }.to raise_error(Google::KeyClient::Error, "Failed to open TCP connection")
    expect(attempts).to eq(2)
  end

  it "doesn't retry a request Google answered" do
    attempts = 0
    google_stubs.get(url) { attempts += 1; [400, {}, {error: {message: "API key not valid"}}.to_json] }

    expect { google_key_client.get(url) }.to raise_error(Google::KeyClient::Error, "API key not valid")
    expect(attempts).to eq(1)
  end
end
