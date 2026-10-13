# encoding: UTF-8

require "rails_helper"

RSpec.describe SyncRequest do
  let!(:enqueued) { stub_sync_kinds }

  def result(created: 0, updated: 0, unchanged: 0, errors: [])
    SyncResult.new(created, updated, unchanged, errors)
  end

  describe ".track" do
    it "records a sync run without a request, and returns its result" do
      returned = travel_to(Time.zone.local(2026, 10, 12, 12)) do
        described_class.track("posts", trigger: "rake", **described_class.range(7)) { result(created: 2, updated: 1) }
      end

      expect(returned.created).to eq(2)
      expect(described_class.first).to have_attributes(
        kind: "posts", trigger: "rake", status: "succeeded", from_date: Date.new(2026, 10, 6), to_date: Date.new(2026, 10, 12),
        created_count: 2, updated_count: 1, unchanged_count: 0, error_count: 0, rows: 3
      )
      expect(described_class.first.duration).to be >= 0
    end

    it "updates the request a job was enqueued for" do
      request = described_class.create!(kind: "posts", trigger: "admin")

      described_class.track("posts", request_id: request.id.to_s) { result(unchanged: 5) }

      expect(described_class.count).to eq(1)
      expect(request.reload).to have_attributes(trigger: "admin", status: "succeeded", unchanged_count: 5)
    end

    it "starts a new request when the one enqueued was deleted meanwhile" do
      described_class.track("posts", request_id: BSON::ObjectId.new.to_s) { result }

      expect(described_class.first).to have_attributes(trigger: "job", status: "succeeded")
    end

    it "counts errors alongside rows as partial, and errors alone as failed" do
      described_class.track("posts") { result(created: 1, errors: ["one bad post"]) }
      described_class.track("pages") { result(errors: ["unreachable"]) }

      expect(described_class.find_by(kind: "posts")).to have_attributes(status: "partial", error_count: 1, error_messages: ["one bad post"])
      expect(described_class.find_by(kind: "pages")).to have_attributes(status: "failed", error_messages: ["unreachable"])
    end

    it "stores only the first errors of a long run, but counts them all" do
      described_class.track("posts") { result(errors: (1..30).map { "post #{it} failed" }) }

      expect(described_class.first).to have_attributes(error_count: 30)
      expect(described_class.first.error_messages.size).to eq(described_class::MAX_STORED_ERRORS)
    end

    it "marks a sync that raised as failed and lets the error through" do
      expect { described_class.track("posts") { raise ArgumentError, "boom" } }.to raise_error(ArgumentError, "boom")

      expect(described_class.first).to have_attributes(status: "failed", error_messages: ["ArgumentError: boom"])
      expect(described_class.first.finished_at).to be_present
    end
  end

  describe ".enqueue and #resync" do
    it "queues the kind's job for the request" do
      request = described_class.enqueue("posts")

      expect(request).to have_attributes(status: "queued", trigger: "admin")
      expect(enqueued).to eq([request])
    end

    it "runs the same sync again as a new request" do
      original = described_class.create!(kind: "pages", trigger: "rake", status: "failed")

      resync = original.resync

      expect(resync).to have_attributes(kind: "pages", trigger: "resync", status: "queued")
      expect(resync.id).not_to eq(original.id)
      expect(enqueued).to eq([resync])
    end
  end

  it "shows a request unfinished for longer than any sync takes as stalled" do
    fresh = described_class.create!(kind: "posts", status: "running")
    old = travel_to(1.hour.ago) { described_class.create!(kind: "posts") }
    done = travel_to(1.hour.ago) { described_class.create!(kind: "posts", status: "succeeded") }

    expect([fresh, old, done].map(&:display_status)).to eq(%w[running stalled succeeded])
    expect([fresh, old, done].map(&:in_progress?)).to eq([true, false, false])
  end

  it "dates a page's data from the last sync that brought any in" do
    travel_to(2.days.ago) { described_class.track("posts") { result(created: 1) } }
    travel_to(1.day.ago) { described_class.track("posts") { result(created: 1, errors: ["one bad"]) } }
    described_class.track("posts") { result(errors: ["down"]) }
    described_class.track("pages") { result(created: 1) }

    expect(described_class.last_completed("posts").status).to eq("partial")
    expect(described_class.latest("posts").status).to eq("failed")
  end

  it "only accepts registered kinds, triggers and statuses" do
    expect(described_class.new(kind: "nope")).not_to be_valid
    expect(described_class.new(kind: "posts", trigger: "nope")).not_to be_valid
    expect(described_class.new(kind: "posts", status: "nope")).not_to be_valid
  end
end
