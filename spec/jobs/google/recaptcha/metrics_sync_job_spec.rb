# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::MetricsSyncJob do
  it "runs a reCAPTCHA metrics sync" do
    allow(Google::Recaptcha::MetricsSyncService).to receive(:call) { SyncResult.new(2, 1, 0, []) }

    described_class.perform_now

    expect(Google::Recaptcha::MetricsSyncService).to have_received(:call)
  end
end
