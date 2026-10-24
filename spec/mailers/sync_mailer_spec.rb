# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncMailer, type: :mailer do
  let(:now) { Time.zone.local(2026, 10, 20, 9) }

  # So specs don't depend on whatever the local credentials hold (CI has none).
  before do
    ActionMailer::Base.deliveries.clear
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :from) { "Blog <blog@domain.com>" }
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :notify_to) { "me@domain.com" }
  end

  def digest_message
    travel_to(now) { described_class.daily_digest.message }
  end

  it "delivers itself to the configured address, summed up in the subject" do
    SyncRequest.create!(
      kind: "feed",
      status: "succeeded",
      trigger: "rake",
      created_at: now - 1.hour,
      finished_at: now - 1.hour
    )

    message = digest_message

    expect(ActionMailer::Base.deliveries).to eq([message])
    expect(message.to).to eq(["me@domain.com"])
    expect(message.subject).to eq("Sync digest: the 1 sync succeeded")
    expect(message.text_part.body.to_s).to include("Feed entries: about 1 hour ago", "Crawled pages: never")
  end

  it "lists each sync that went wrong with its first errors, escaped" do
    SyncRequest.create!(
      kind: "analytics",
      status: "partial",
      trigger: "rake",
      created_at: now - 1.hour,
      finished_at: now - 1.hour,
      error_count: 5,
      error_messages: ["Day <1> failed", "Day 2 failed", "Day 3 failed", "Day 4 failed"]
    )

    message = digest_message
    html = message.html_part.body.to_s
    text = message.text_part.body.to_s

    expect(message.subject).to eq("Sync digest: 1 with errors of 1")
    expect(html).to include("Needs a look", "With errors", "Day &lt;1&gt; failed", "Day 3 failed", "and 2 more errors")
    expect(html).not_to include("Day 4 failed")
    expect(text).to include("- Analytics acquisition, engagement, users & retention: With errors", "  Day <1> failed", "  and 2 more errors")
  end
end
