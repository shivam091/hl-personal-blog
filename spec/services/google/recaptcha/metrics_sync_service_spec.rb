# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::MetricsSyncService do
  let(:url) { "https://recaptchaenterprise.googleapis.com/v1/projects/blog-project/keys/site-key/metrics" }

  def sync
    described_class.call(project: "blog-project", site_key: "site-key", client: google_client)
  end

  it "stores each day's score breakdown, counting days from the start time" do
    google_stubs.get(url) do
      [200, {}, {
        startTime: "2026-10-09T00:00:00Z",
        scoreMetrics: [
          {overallMetrics: {scoreBuckets: {"10" => "2", "90" => "10"}}, actionMetrics: {login: {scoreBuckets: {"90" => "3"}}}},
          {overallMetrics: {scoreBuckets: {"70" => "4"}}}
        ]
      }.to_json]
    end

    expect(sync.summary).to eq("2 created, 0 updated, 0 unchanged, 0 failed")
    first, second = Google::Recaptcha::Stat.order(date: :asc).to_a
    expect(first).to have_attributes(
      date: Date.new(2026, 10, 9), scores: [{"score" => 0.9, "count" => 10}, {"score" => 0.1, "count" => 2}],
      action_scores: {"login" => [{"score" => 0.9, "count" => 3}]}, challenges: {}, requests: 12
    )
    expect(second).to have_attributes(date: Date.new(2026, 10, 10), scores: [{"score" => 0.7, "count" => 4}])
  end

  it "stores challenge counts for checkbox keys and leaves unchanged days alone" do
    Google::Recaptcha::Stat.create!(date: Date.new(2026, 10, 9), challenges: {"page_loads" => 5, "no_challenge" => 4, "passed" => 1, "failed" => 0})
    google_stubs.get(url) do
      [200, {}, {
        startTime: "2026-10-09T00:00:00Z",
        challengeMetrics: [
          {pageloadCount: "5", nocaptchaCount: "4", passedCount: "1", failedCount: "0"},
          {pageloadCount: "8", nocaptchaCount: "6", passedCount: "1", failedCount: "1"}
        ]
      }.to_json]
    end

    expect(sync.summary).to eq("1 created, 0 updated, 1 unchanged, 0 failed")
    expect(Google::Recaptcha::Stat.find_by(date: Date.new(2026, 10, 10)).challenges).to eq("page_loads" => 8, "no_challenge" => 6, "passed" => 1, "failed" => 1)
  end

  it "handles a key with no data yet" do
    google_stubs.get(url) { [200, {}, {name: "projects/blog-project/keys/site-key/metrics"}.to_json] }

    expect(sync.summary).to eq("0 created, 0 updated, 0 unchanged, 0 failed")
  end

  it "reports an API error instead of raising" do
    google_stubs.get(url) { [403, {}, {error: {message: "Permission 'recaptchaenterprise.metrics.get' denied"}}.to_json] }

    expect(sync.errors).to eq(["reCAPTCHA: Permission 'recaptchaenterprise.metrics.get' denied"])
  end

  it "reports missing configuration" do
    expect(described_class.call(project: nil, site_key: "k", client: google_client).errors.first).to include("google.recaptcha_project_id")
    expect(described_class.call(project: "p", site_key: nil, client: google_client).errors.first).to include("recaptcha.site_key")
  end
end
