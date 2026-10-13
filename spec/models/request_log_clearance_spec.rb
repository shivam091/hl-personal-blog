# encoding: UTF-8

require "rails_helper"

RSpec.describe RequestLogClearance do
  let(:ist) { Time.find_zone("Asia/Kolkata") }

  def log_at(time, id, uri: "https://admin.example.com/")
    RequestLog.create!(uuid: id, uri: uri, request_method: "GET", status: 200, created_at: time)
  end

  it "covers whole days in IST, from the first day's start to the last day's end" do
    log_at(ist.local(2026, 9, 30, 23, 59), "before")
    log_at(ist.local(2026, 10, 1, 0, 0), "first")
    log_at(ist.local(2026, 10, 2, 23, 59, 59), "last")
    log_at(ist.local(2026, 10, 3, 0, 0), "after")

    clearance = described_class.new(from: "2026-10-01", to: "2026-10-02")

    expect(clearance.scope.pluck(:_id)).to contain_exactly("first", "last")
  end

  it "can narrow the range to local request logs, keeping production's" do
    log_at(ist.local(2026, 10, 1, 12), "production")
    log_at(ist.local(2026, 10, 1, 13), "local", uri: "http://localhost:3000/request-logs")
    log_at(ist.local(2026, 10, 5, 12), "local-outside-range", uri: "http://localhost:3000/")

    clearance = described_class.new(from: "2026-10-01", to: "2026-10-02", local_only: "1")

    expect(clearance.local_only).to be_truthy
    expect(clearance.scope.pluck(:_id)).to eq(["local"])
    expect(described_class.new.local_only).to be_falsy
  end

  it "requires both dates, valid, and in order" do
    blank = described_class.new.tap(&:validate)
    expect(blank.errors.full_messages).to contain_exactly("Start date can't be blank", "End date can't be blank")

    mistyped = described_class.new(from: "2026-13-45", to: "2026-10-01").tap(&:validate)
    expect(mistyped.errors.full_messages).to eq(["Start date is not a valid date"])

    backwards = described_class.new(from: "2026-10-05", to: "2026-10-01").tap(&:validate)
    expect(backwards.errors.full_messages).to eq(["End date can't be before the start date"])

    expect(described_class.new(from: "2026-10-01", to: "2026-10-01")).to be_valid
  end

  it "enqueues the clearing job with ISO dates and whether it's local only" do
    expect { described_class.new(from: "2026-10-01", to: "2026-10-02").enqueue }
      .to have_enqueued_job(ClearRequestLogsJob).with("2026-10-01", "2026-10-02", local_only: false)
    expect { described_class.new(from: "2026-10-01", to: "2026-10-02", local_only: "1").enqueue }
      .to have_enqueued_job(ClearRequestLogsJob).with("2026-10-01", "2026-10-02", local_only: true)
  end
end
