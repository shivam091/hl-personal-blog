# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::Verifier do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) { Faraday.new { |faraday| faraday.response :raise_error; faraday.adapter :test, stubs } }
  let(:assessments_url) { "https://recaptchaenterprise.googleapis.com/v1/projects/blog-project/assessments" }
  let(:sent) { [] }

  describe "through siteverify, while no Enterprise project is configured" do
    def verifier(**options)
      described_class.new(site_key: "site", secret_key: "secret", project: nil, connection: connection, client: google_client, **options)
    end

    def stub_verdict(**verdict)
      stubs.post(described_class::VERIFY_URL) do |env|
        sent << URI.decode_www_form(env.body).to_h
        [200, {},
          {
            success: true,
            action: "login",
            score: 0.9,
            hostname: "admin.example.com",
            challenge_ts: "2026-10-11T10:00:00Z"
          }.merge(verdict).to_json
        ]
      end
    end

    it "passes a confident token for the expected action, sending the secret and client IP, and records the check" do
      stub_verdict

      verdict = verifier.check("token", action: "login", remote_ip: "203.0.113.5", user_agent: "Firefox")
      expect(verdict).to be_human
      expect(sent.sole).to eq("secret" => "secret", "response" => "token", "remoteip" => "203.0.113.5")
      expect(verdict.assessment).to be_persisted
      expect(Google::Recaptcha::Assessment.all.sole).to have_attributes(
        name: nil, action: "login", expected_action: "login", score: 0.9, valid_token: true, hostname: "admin.example.com",
        token_created_at: Time.utc(2026, 10, 11, 10), remote_ip: "203.0.113.5", user_agent: "Firefox", accepted: true
      )
    end

    it "rejects a low score, using the configured threshold" do
      stub_verdict(score: 0.6)

      expect(verifier.check("token", action: "login")).to be_human
      expect(verifier(min_score: 0.7).check("token", action: "login")).not_to be_human
      expect(Google::Recaptcha::Assessment.order(created_at: :asc).last.accepted).to be_falsy
    end

    it "rejects an invalid token or one for another action" do
      stub_verdict(success: false, "error-codes": ["timeout-or-duplicate"])
      expect(verifier.check("token", action: "login")).not_to be_human
      expect(Google::Recaptcha::Assessment.all.sole).to have_attributes(valid_token: false, invalid_reason: "timeout-or-duplicate", accepted: false)

      stubs = Faraday::Adapter::Test::Stubs.new do |s|
        s.post(described_class::VERIFY_URL) { [200, {}, {success: true, action: "contact", score: 0.9}.to_json] }
      end
      other = described_class.new(
        site_key: "site",
        secret_key: "secret",
        project: nil,
        connection: Faraday.new { |f| f.adapter :test, stubs }
      )
      expect(other.check("token", action: "login")).not_to be_human
    end

    it "rejects a missing token without asking Google" do
      verdict = verifier.check("", action: "login")

      expect(verdict).not_to be_human
      expect(verdict.assessment).to be_nil
    end

    it "lets the request through when Google can't be reached" do
      stubs.post(described_class::VERIFY_URL) { raise Faraday::ConnectionFailed, "down" }

      expect(verifier.check("token", action: "login")).to be_human
    end
  end

  describe "through reCAPTCHA Enterprise" do
    def verifier(**options)
      described_class.new(site_key: "site", secret_key: nil, project: "blog-project", client: google_client, **options)
    end

    def stub_assessment(risk: {}, token: {})
      google_stubs.post(assessments_url) do |env|
        sent << JSON.parse(env.body)
        [200, {}, {
          name: "projects/123/assessments/abc",
          riskAnalysis: {score: 0.9, reasons: []}.merge(risk),
          tokenProperties: {valid: true, invalidReason: "INVALID_REASON_UNSPECIFIED", action: "login", hostname: "admin.example.com", createTime: "2026-10-11T10:00:00Z"}.merge(token)
        }.to_json]
      end
    end

    it "is enabled without a secret key, and records Google's assessment" do
      stub_assessment

      expect(verifier).to be_enabled
      expect(verifier.check("token", action: "login", remote_ip: "203.0.113.5", user_agent: "Firefox")).to be_human
      expect(sent.sole).to eq("event" => {"token" => "token", "siteKey" => "site", "expectedAction" => "login", "userIpAddress" => "203.0.113.5", "userAgent" => "Firefox"})
      expect(Google::Recaptcha::Assessment.all.sole).to have_attributes(
        name: "projects/123/assessments/abc", score: 0.9, reasons: [], valid_token: true, invalid_reason: nil, action: "login", accepted: true
      )
    end

    it "records why Google scored a token low" do
      stub_assessment(risk: {score: 0.1, reasons: %w[AUTOMATION TOO_MUCH_TRAFFIC]})

      expect(verifier.check("token", action: "login")).not_to be_human
      expect(Google::Recaptcha::Assessment.all.sole).to have_attributes(score: 0.1, reasons: %w[AUTOMATION TOO_MUCH_TRAFFIC], accepted: false)
    end

    it "rejects an invalid token, keeping Google's reason" do
      stub_assessment(risk: {score: 0.0}, token: {valid: false, invalidReason: "EXPIRED", action: ""})

      expect(verifier.check("token", action: "login")).not_to be_human
      expect(Google::Recaptcha::Assessment.all.sole).to have_attributes(valid_token: false, invalid_reason: "EXPIRED")
    end

    it "lets the request through when Google refuses the check" do
      google_stubs.post(assessments_url) { [403, {}, {error: {message: "Permission 'recaptchaenterprise.assessments.create' denied"}}.to_json] }

      expect(verifier.check("token", action: "login")).to be_human
      expect(Google::Recaptcha::Assessment.count).to eq(0)
    end
  end

  it "passes everything while the keys aren't set" do
    verifier = described_class.new(site_key: "", secret_key: nil, project: "blog-project", client: google_client)

    expect(verifier).not_to be_enabled
    expect(verifier.check(nil, action: "login")).to be_human
  end
end
