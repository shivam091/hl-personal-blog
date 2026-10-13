# encoding: UTF-8

require "rails_helper"

RSpec.describe ExternalCallRecorder do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }

  def connection(service: nil)
    Faraday.new do |faraday|
      faraday.use described_class, service: service
      faraday.response :raise_error
      faraday.adapter :test, stubs
    end
  end

  it "records a successful call with its service, status, size and duration" do
    stubs.post("https://searchconsole.googleapis.com/v1/urlInspection/index:inspect") { [200, {}, '{"ok":true}'] }

    connection.post("https://searchconsole.googleapis.com/v1/urlInspection/index:inspect", "{}")

    expect(ExternalCall.last).to have_attributes(
      service: "Search Console", http_method: "POST", host: "searchconsole.googleapis.com",
      status: 200, response_size: 11, error: nil
    )
    expect(ExternalCall.last.duration_ms).to be >= 0
  end

  it "uses the service it was given when the host doesn't name one" do
    stubs.get("https://blog.example/feed.xml") { [200, {}, "<feed/>"] }

    connection(service: "Atom feed").get("https://blog.example/feed.xml")

    expect(ExternalCall.last.service).to eq("Atom feed")
  end

  it "records a refusal with Google's explanation, and still raises" do
    stubs.get("https://www.googleapis.com/pagespeedonline/v5/runPagespeed") { [403, {}, '{"error":{"message":"API key not valid"}}'] }

    expect { connection.get("https://www.googleapis.com/pagespeedonline/v5/runPagespeed", key: "secret-key") }.to raise_error(Faraday::ForbiddenError)

    expect(ExternalCall.last).to have_attributes(service: "PageSpeed Insights", status: 403, error_body: include("API key not valid"))
    expect(ExternalCall.last.url).to include("key=%5BFILTERED%5D")
    expect(ExternalCall.last.url).not_to include("secret-key")
  end

  it "records a call that got no response" do
    stubs.get("https://chromeuxreport.googleapis.com/v1/x") { raise Faraday::TimeoutError, "timeout" }

    expect { connection.get("https://chromeuxreport.googleapis.com/v1/x") }.to raise_error(Faraday::TimeoutError)

    expect(ExternalCall.last).to have_attributes(service: "Chrome UX Report", status: nil, error: "timeout")
  end

  it "lets the call through when it can't be recorded" do
    allow(ExternalCall).to receive(:create!).and_raise(Mongo::Error::SocketError, "down")
    stubs.get("https://blog.example/sitemap.xml") { [200, {}, "<urlset/>"] }

    expect(connection(service: "Blog sitemap").get("https://blog.example/sitemap.xml").status).to eq(200)
  end
end
