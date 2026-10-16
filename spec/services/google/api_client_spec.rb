# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::ApiClient do
  let(:url) { "https://example.googleapis.com/v1/report" }

  it "signs a service-account assertion and calls the API with the token it gets" do
    assertion = nil
    google_stubs.post(Google::ApiClient::TOKEN_URL) do |env|
      assertion = URI.decode_www_form(env.body).to_h.fetch("assertion")
      [200, {}, {access_token: "token-123"}.to_json]
    end
    google_stubs.post(url) do |env|
      expect(env.request_headers["Authorization"]).to eq("Bearer token-123")
      expect(JSON.parse(env.body)).to eq("a" => 1)
      [200, {}, {rows: []}.to_json]
    end

    expect(google_client(scope: "s1").post(url, {a: 1})).to eq("rows" => [])

    signing_input, signature = assertion.rpartition(".").values_at(0, 2)
    claims = JSON.parse(Base64.urlsafe_decode64(signing_input.split(".").last))
    expect(claims).to include("iss" => "sync@project.iam.gserviceaccount.com", "scope" => "s1", "aud" => Google::ApiClient::TOKEN_URL)
    expect(GoogleApiHelpers::GOOGLE_TEST_KEY.public_key.verify("SHA256", Base64.urlsafe_decode64(signature), signing_input)).to be_truthy
  end

  it "reuses its token across requests" do
    token_calls = 0
    google_stubs.post(Google::ApiClient::TOKEN_URL) { token_calls += 1; [200, {}, {access_token: "t"}.to_json] }
    google_stubs.post(url) { [200, {}, "{}"] }
    client = google_client

    2.times { client.post(url, {}) }

    expect(token_calls).to eq(1)
  end

  it "repeats a parameter given a list, as Google expects" do
    query = nil
    google_stubs.get(url) do |env|
      query = env.url.query
      [200, {}, "{}"]
    end

    google_client.get(url, "filter" => "a", "aggregation.groupByFields" => ["resource.label.service", "resource.label.method"])

    expect(URI.decode_www_form(query)).to contain_exactly(
      ["filter", "a"],
      ["aggregation.groupByFields", "resource.label.service"],
      ["aggregation.groupByFields", "resource.label.method"]
    )
  end

  it "accepts a key with escaped line breaks, as copied from the JSON file" do
    google_stubs.post(url) { [200, {}, "{}"] }

    expect(google_client(private_key: GoogleApiHelpers::GOOGLE_TEST_KEY.to_pem.gsub("\n", "\\n")).post(url, {})).to eq({})
  end

  it "raises Google's own explanation of an error" do
    google_stubs.post(url) { [403, {}, {error: {code: 403, message: "User does not have sufficient permission for site"}}.to_json] }

    expect { google_client.post(url, {}) }.to raise_error(Google::ApiClient::Error, "User does not have sufficient permission for site")
  end

  it "tries once more when the connection doesn't open" do
    attempts = 0
    google_stubs.post(url) do
      attempts += 1
      raise Faraday::ConnectionFailed, "Failed to open TCP connection" if attempts == 1
      [200, {}, {rows: []}.to_json]
    end
    client = google_client
    allow(client).to receive(:sleep)

    expect(client.post(url, {})).to eq("rows" => [])
    expect(attempts).to eq(2)
  end

  it "gives up after the second failed connection" do
    attempts = 0
    google_stubs.post(url) { attempts += 1; raise Faraday::ConnectionFailed, "Failed to open TCP connection" }
    client = google_client
    allow(client).to receive(:sleep)

    expect { client.post(url, {}) }.to raise_error(Google::ApiClient::Error, "Failed to open TCP connection")
    expect(attempts).to eq(2)
  end

  it "gives up at once when told not to retry" do
    attempts = 0
    google_stubs.post(url) { attempts += 1; raise Faraday::ConnectionFailed, "Failed to open TCP connection" }

    expect { google_client(retry_connect: false).post(url, {}) }.to raise_error(Google::ApiClient::Error, "Failed to open TCP connection")
    expect(attempts).to eq(1)
  end

  it "doesn't retry a request Google answered" do
    attempts = 0
    google_stubs.post(url) { attempts += 1; [500, {}, "{}"] }

    expect { google_client.post(url, {}) }.to raise_error(Google::ApiClient::Error)
    expect(attempts).to eq(1)
  end

  it "explains a refused token" do
    google_stubs.post(Google::ApiClient::TOKEN_URL) { [400, {}, {error: "invalid_grant", error_description: "Invalid JWT Signature."}.to_json] }

    expect { google_client.post(url, {}) }.to raise_error(Google::ApiClient::Error, "Couldn't get a Google access token: Invalid JWT Signature.")
  end

  it "rejects a key that isn't PEM" do
    expect { google_client(private_key: "not a key").post(url, {}) }.to raise_error(Google::ApiClient::Error, /isn't a valid PEM key/)
  end

  it "knows whether it's configured" do
    expect(google_client).to be_configured
    expect(google_client(client_email: nil)).not_to be_configured
    expect(google_client(private_key: "")).not_to be_configured
  end
end
