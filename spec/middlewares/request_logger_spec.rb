# encoding: UTF-8

require "rails_helper"

RSpec.describe RequestLogger do
  describe "in the app", type: :request do
    it "logs each request once its response is sent, attributed to the admin" do
      RequestLog.delete_all

      get crawled_pages_path(q: "css"), headers: {"User-Agent" => "RSpec", "X-Request-Id" => "spec-request-1"}

      log = RequestLog.find("spec-request-1")
      expect(log).to have_attributes(
        request_method: "GET", status: 200, user: AuthenticationHelpers::ADMIN_USERNAME,
        uri: "http://www.example.com/crawled-pages?q=css", query_params: {"q" => "css"},
        remote_address: "127.0.0.1", user_agent: "RSpec", response_size: response.body.bytesize
      )
      expect(log.session_id).to be_present
      expect(log.elapsed_time).to be > 0
      expect(log.memory_usage).to be > 0
      expect(log.request_headers).to include("User-Agent" => "RSpec", "X-Request-Id" => "spec-request-1")
      expect(log.request_headers).not_to have_key("Cookie")
      expect(log.response_headers).to include("content-type" => a_string_including("text/html"))
      expect(log.response_headers).not_to have_key("set-cookie")
    end

    it "keeps passwords out of the logged params", :signed_out do
      RequestLog.delete_all

      post session_path, params: {username: "admin", password: "hunter2"}, headers: {"X-Request-Id" => "login"}

      expect(RequestLog.find("login").query_params).to include("username" => "admin", "password" => "[FILTERED]")
    end

    it "logs uploaded files by name, since MongoDB can't store them" do
      file = Rack::Test::UploadedFile.new(StringIO.new("URL\n"), "text/csv", original_filename: "pages.csv")

      post import_crawled_pages_path, params: {file: file}, headers: {"X-Request-Id" => "upload"}

      expect(RequestLog.find("upload").query_params["file"]).to eq("#<file pages.csv (4 bytes)>")
    end

    it "skips health checks" do
      RequestLog.delete_all

      get rails_health_check_path

      expect(RequestLog.count).to eq(0)
    end
  end

  describe "when the app raises" do
    it "logs the exception and its status, then re-raises it" do
      app = described_class.new(->(_env) { raise Mongoid::Errors::DocumentNotFound.new(RequestLog, ["missing"]) })
      env = Rack::MockRequest.env_for("/request-logs/missing", "action_dispatch.request_id" => "raised")

      expect { app.call(env) }.to raise_error(Mongoid::Errors::DocumentNotFound)

      log = RequestLog.find("raised")
      expect(log.status).to eq(404)
      expect(log.exception["class"]).to eq("Mongoid::Errors::DocumentNotFound")
      expect(log).to be_error
    end
  end

  describe "when logging fails" do
    it "still returns the response" do
      allow(RequestLog).to receive(:create!).and_raise(Mongo::Error, "down")
      app = described_class.new(->(_env) { [200, {"content-type" => "text/plain"}, ["ok"]] })

      status, _headers, body = app.call(Rack::MockRequest.env_for("/"))
      body.each { |_chunk| } # rubocop:disable Lint/EmptyBlock -- the server reads the body before closing it
      body.close

      expect(status).to eq(200)
    end
  end

  it "keeps credentials out of the logged headers" do
    app = described_class.new(->(_env) { [200, {"set-cookie" => "session=abc"}, []] })
    env = Rack::MockRequest.env_for("/", "action_dispatch.request_id" => "headers",
      "HTTP_COOKIE" => "session=abc", "HTTP_AUTHORIZATION" => "Bearer x", "HTTP_X_FORWARDED_FOR" => "203.0.113.9")

    app.call(env).last.close

    log = RequestLog.find("headers")
    expect(log.request_headers).to include("X-Forwarded-For" => "203.0.113.9")
    expect(log.request_headers.keys).not_to include("Cookie", "Authorization")
    expect(log.response_headers).not_to have_key("set-cookie")
  end

  it "counts the bytes of streamed bodies" do
    app = described_class.new(->(_env) { [200, {}, ["ab", "cde"]] })
    env = Rack::MockRequest.env_for("/", "action_dispatch.request_id" => "counted")

    _status, _headers, body = app.call(env)
    body.each { |_chunk| } # rubocop:disable Lint/EmptyBlock -- the server reads the body before closing it
    body.close

    expect(RequestLog.find("counted").response_size).to eq(5)
  end
end
