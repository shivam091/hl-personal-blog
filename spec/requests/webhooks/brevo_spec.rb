# encoding: UTF-8

require "rails_helper"

RSpec.describe "Brevo webhook", type: :request, signed_out: true do
  let(:event) do
    {"event" => "unique_opened", "email" => "reader@example.com", "message-id" => "<abc@smtp-relay.mailin.fr>",
     "tags" => ["https://blog.example.com/post/a"], "ts_epoch" => 1_790_000_000_000}
  end

  around { |example| with_token("s3cret") { example.run } }

  def with_token(token)
    previous = ENV["BREVO_WEBHOOK_TOKEN"]
    ENV["BREVO_WEBHOOK_TOKEN"] = token
    yield
  ensure
    ENV["BREVO_WEBHOOK_TOKEN"] = previous
  end

  def post_events(body, token: "s3cret")
    post webhooks_brevo_path(token: token), params: body.to_json, headers: {"Content-Type" => "application/json"}
  end

  it "stores an event posted with the shared secret, without a session or CSRF token" do
    ActionController::Base.allow_forgery_protection = true
    post_events(event)

    expect(response).to have_http_status(:ok)
    expect(NewsletterEmailEvent.all.sole.attributes.slice("event", "tag")).to eq("event" => "unique_opened", "tag" => "https://blog.example.com/post/a")
  ensure
    ActionController::Base.allow_forgery_protection = false
  end

  it "takes a batch, storing an event Brevo retries once" do
    post_events([event, event, event.merge("event" => "click", "link" => "https://blog.example.com/post/a")])
    post_events(event)

    expect(response).to have_http_status(:ok)
    expect(NewsletterEmailEvent.pluck(:event)).to contain_exactly("unique_opened", "click")
  end

  it "accepts events it doesn't keep, so Brevo doesn't retry them" do
    post_events(event.merge("event" => "request"))

    expect(response).to have_http_status(:ok)
    expect(NewsletterEmailEvent.count).to eq(0)
  end

  it "refuses a wrong or missing secret" do
    post_events(event, token: "wrong")
    expect(response).to have_http_status(:unauthorized)

    post_events(event, token: nil)
    expect(response).to have_http_status(:unauthorized)
    expect(NewsletterEmailEvent.count).to eq(0)
  end

  it "refuses everything while no secret is configured" do
    with_token(nil) { post_events(event, token: "") }

    expect(response).to have_http_status(:unauthorized)
  end

  it "rejects a body that isn't events" do
    post webhooks_brevo_path(token: "s3cret"), params: "not json", headers: {"Content-Type" => "text/plain"}
    expect(response).to have_http_status(:bad_request)

    post_events(["not an event"])
    expect(response).to have_http_status(:bad_request)
  end

  it "keeps the secret out of the request log" do
    post_events(event)

    expect(RequestLog.last.uri).not_to include("s3cret")
  end
end
