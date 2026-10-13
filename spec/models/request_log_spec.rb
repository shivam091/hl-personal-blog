# encoding: UTF-8

require "rails_helper"

RSpec.describe RequestLog do
  def build_log(**attributes)
    described_class.new(uri: "https://admin.example.com/crawled-pages?page=2", request_method: "GET", status: 200, **attributes)
  end

  it "is keyed by the request id" do
    log = build_log(uuid: "3f1c-request-id")
    log.save!

    expect(described_class.find("3f1c-request-id")).to eq(log)
    expect(log.id).to eq("3f1c-request-id")
  end

  it "upcases the request method" do
    log = build_log(request_method: "post".freeze)
    log.validate

    expect(log.request_method).to eq("POST")
  end

  it "shows the path with its query" do
    expect(build_log.path).to eq("/crawled-pages?page=2")
    expect(build_log.to_s).to eq("GET /crawled-pages?page=2")
  end

  # Logs are only removed when the admin deletes them; a TTL index would
  # delete them behind their back.
  it "never expires logs on its own" do
    expect(described_class.index_specifications.map { |spec| spec.options[:expire_after] }).to all(be_nil)
  end

  describe ".local" do
    it "matches requests to a local server by the URL's host, with or without a port" do
      local = ["http://localhost:3000/crawled-pages", "http://LOCALHOST/", "http://127.0.0.1:3000", "http://[::1]:3000/up?x=1"]
      production = ["https://hl-personal-blog.onrender.com/", "http://localhost.example.com/", "http://example.com/localhost"]
      (local + production).each_with_index do |uri, n|
        RequestLog.create!(uuid: "log-#{n}", uri: uri, request_method: "GET", status: 200)
      end

      expect(RequestLog.local.pluck(:uri)).to match_array(local)
    end

    it "ignores the client address, since production's health probes come from loopback" do
      RequestLog.create!(uri: "http://hl-personal-blog.onrender.com/", request_method: "HEAD", status: 302, remote_address: "127.0.0.1")

      expect(RequestLog.local.count).to eq(0)
    end
  end

  describe ".to_csv" do
    it "exports one row per log" do
      build_log(
        uuid: "req-1", status: 500, elapsed_time: 0.1234, response_size: 512, remote_address: "203.0.113.9",
        ip_info: {"country" => "India", "city" => "Pune", "org" => "AS1 Example"},
        exception: {"class" => "RuntimeError", "message" => "boom"}
      ).save!

      rows = CSV.parse(described_class.to_csv(described_class.all))

      expect(rows.first).to eq(RequestLog::CSV_HEADERS)
      expect(rows.second).to include("req-1", "GET", "500", "123.4", "512", "203.0.113.9", "India", "Pune", "AS1 Example", "RuntimeError: boom")
    end
  end
end
