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

  it "says when a consent snapshot is missing, though no sync failed" do
    SyncRequest.create!(kind: "feed", status: "succeeded", created_at: now - 1.hour, finished_at: now - 1.hour)
    ConsentSnapshot.create!(day: "2026-10-01")

    message = digest_message

    expect(message.subject).to eq("Sync digest: the 1 sync succeeded, and no consent snapshot for #{I18n.l(Date.new(2026, 10, 18), format: :short)}")
    expect(message.html_part.body.to_s).to include("Some syncs need a look", "Consent snapshots", "Missing", I18n.l(Date.new(2026, 10, 18)))
    expect(message.text_part.body.to_s).to include("- Consent snapshots: Missing")

    ConsentSnapshot.create!(day: "2026-10-18")

    expect(digest_message.subject).to eq("Sync digest: the 1 sync succeeded")
  end

  it "says what share of our views GA saw last week against the usual week, once both are known" do
    SyncRequest.create!(kind: "feed", status: "succeeded", created_at: now - 1.hour, finished_at: now - 1.hour)
    {"2026-10-15" => 30, "2026-10-08" => 70, "2026-10-01" => 80, "2026-09-24" => 60}.each do |day, analytics|
      ConsentSnapshot.create!(day: day, first_party: 100, analytics: analytics)
    end

    message = digest_message

    expect(message.html_part.body.to_s).to include("GA saw 30% of our views last week (usual 70%).")
    expect(message.text_part.body.to_s).to include("GA saw 30% of our views last week (usual 70%).")
  end

  it "leaves the share out without enough earlier weeks to call one usual" do
    SyncRequest.create!(kind: "feed", status: "succeeded", created_at: now - 1.hour, finished_at: now - 1.hour)
    ConsentSnapshot.create!(day: "2026-10-15", first_party: 100, analytics: 30)
    ConsentSnapshot.create!(day: "2026-10-08", first_party: 100, analytics: 70)

    expect(digest_message.text_part.body.to_s).not_to include("GA saw")
  end

  it "asks for the Generative AI report again once its upload is out of date" do
    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web (text-based)", date: Date.new(2026, 10, 1), impressions: 3)

    message = digest_message

    expect(message.text_part.body.to_s).to include("Generative AI upload: Out of date", "Web (text-based) figures stop at")
    expect(message.html_part.body.to_s).to include("Generative AI upload", "Out of date")
  end
end
