# encoding: UTF-8

require "rails_helper"

RSpec.describe ClearRequestLogsJob do
  let(:ist) { Time.find_zone("Asia/Kolkata") }

  def log_at(time, id, uri: "https://admin.example.com/")
    RequestLog.create!(uuid: id, uri: uri, request_method: "GET", status: 200, created_at: time)
  end

  it "deletes only the logs in the range" do
    log_at(ist.local(2026, 9, 30, 12), "keep-before")
    log_at(ist.local(2026, 10, 1, 12), "clear")
    log_at(ist.local(2026, 10, 3, 12), "keep-after")

    described_class.perform_now("2026-10-01", "2026-10-02")

    expect(RequestLog.pluck(:_id)).to contain_exactly("keep-before", "keep-after")
  end

  it "deletes only local logs in the range when asked to" do
    log_at(ist.local(2026, 10, 1, 12), "keep-production")
    log_at(ist.local(2026, 10, 1, 13), "clear-local", uri: "http://localhost:3000/")
    log_at(ist.local(2026, 10, 3, 12), "keep-local-after", uri: "http://localhost:3000/")

    described_class.perform_now("2026-10-01", "2026-10-02", local_only: true)

    expect(RequestLog.pluck(:_id)).to contain_exactly("keep-production", "keep-local-after")
  end

  it "refuses an invalid range rather than guessing" do
    log_at(ist.local(2026, 10, 1, 12), "keep")

    expect { described_class.perform_now("2026-10-05", "2026-10-01") }.to raise_error(ArgumentError, /before the start date/)
    expect(RequestLog.count).to eq(1)
  end
end
