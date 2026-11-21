# encoding: UTF-8

require "rails_helper"

RSpec.describe MonitoringReview do
  describe ".clear" do
    it "deletes request logs and external calls from before today, keeping today's" do
      travel_to Time.zone.parse("2026-11-23 05:30") do
        old = 1.hour.ago.beginning_of_day - 1.minute
        RequestLog.create!(uri: "/old", request_method: "GET", status: 200, created_at: old)
        RequestLog.create!(uri: "/new", request_method: "GET", status: 200, created_at: 1.minute.ago)
        ExternalCall.create!(service: "Search Console", http_method: "GET", url: "https://a.test/", status: 200, created_at: old)

        expect(described_class.clear).to eq(request_logs: 1, external_calls: 1)
        expect(RequestLog.pluck(:uri)).to eq(["/new"])
      end
    end
  end
end
