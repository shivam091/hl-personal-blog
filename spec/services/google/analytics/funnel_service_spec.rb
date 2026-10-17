# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::FunnelService do
  let(:url) { "https://analyticsdata.googleapis.com/v1alpha/properties/123456789:runFunnelReport" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }
  let(:bodies) { [] }
  let(:steps) {
    [
      ["1. Visited the blog", 100, 0.4, 60, 0.6],
      ["2. Read an entry", 40, 0.05, 38, 0.95],
      ["3. Subscribed to the newsletter", 2, 0, 0, 0]
    ]
  }

  def table(*rows)
    {
      funnelTable: {
        dimensionHeaders: [{name: "funnelStepName"}],
        metricHeaders: %w[activeUsers funnelStepCompletionRate funnelStepAbandonments funnelStepAbandonmentRate].map { |name| {name: name} },
        rows: rows.map do |name, *values|
          {
            dimensionValues: [{value: name}], metricValues: values.map { |value| {value: value.to_s} }
          }
        end
      }
    }
  end

  def funnels(property: 123456789)
    described_class.new(property: property, client: google_client, cache: cache).call(period)
  end

  before do
    google_stubs.post(url) do |env|
      bodies << JSON.parse(env.body)
      [200, {}, table(*steps).to_json]
    end
  end

  it "reads each funnel's steps in order, with GA's completion and abandonment" do
    result = funnels

    expect(result.errors).to eq([])
    newsletter = result.funnels.first
    expect(newsletter.steps.map(&:to_h)).to eq([
      {name: "Visited the blog", users: 100, completion_rate: 0.4, abandonments: 60, abandonment_rate: 0.6},
      {name: "Read an entry", users: 40, completion_rate: 0.05, abandonments: 38, abandonment_rate: 0.95},
      {name: "Subscribed to the newsletter", users: 2, completion_rate: 0.0, abandonments: 0, abandonment_rate: 0.0}
    ])
    expect(newsletter.conversion_rate).to eq(0.02)
  end

  it "keeps the steps before a conversion to the live site, and entry reads to entry pages" do
    funnels

    steps = bodies.first.dig("funnel", "steps")
    expect(bodies.first["dateRanges"]).to eq([{"startDate" => "2026-10-01", "endDate" => "2026-10-12"}])
    expect(steps.map { |step| step["name"] }).to eq(["Visited the blog", "Read an entry", "Subscribed to the newsletter"])

    read = steps.second.dig("filterExpression", "andGroup", "expressions")
    expect(read.first).to eq("funnelEventFilter" => {"eventName" => "page_view"})
    expect(read.second.dig("funnelFieldFilter", "fieldName")).to eq("hostName")

    entry_filters = read.third.dig("orGroup", "expressions").map { |expression| expression["funnelFieldFilter"] }
    expect(entry_filters.map { |filter| filter.dig("stringFilter", "value") }).to eq(%w[/post/ /tutorial/ /snippet/])
    expect(entry_filters.map { |filter| filter["fieldName"] }.uniq).to eq(["pagePathPlusQueryString"])
    expect(steps.third["filterExpression"]).to eq("funnelEventFilter" => {"eventName" => "newsletter_subscribe"})
  end

  # GA refuses pagePath inside funnel steps.
  it "matches the contact page with or without a query string" do
    funnels

    contact = bodies.second.dig("funnel", "steps").second.dig("filterExpression", "andGroup", "expressions").third["funnelFieldFilter"]
    expect(contact["fieldName"]).to eq("pagePathPlusQueryString")
    expect(contact["stringFilter"]).to include("matchType" => "FULL_REGEXP", "value" => "/contact(\\?.*)?")
  end

  it "reads each value by its own header when GA lists the headers twice" do
    google_stubs.post(url) do
      report = table(*steps)
      report[:funnelTable][:metricHeaders] *= 2
      [200, {}, report.to_json]
    end

    expect(funnels.funnels.first.steps.map(&:users)).to eq([100, 40, 2])
  end

  it "asks GA once per funnel and period while cached" do
    2.times { funnels }

    expect(bodies.size).to eq(4)
  end

  # The share bar is only on entries, and both events come from the browser.
  it "counts shares made from entries on the live site, and resume downloads from any page" do
    funnels

    share = bodies.third.dig("funnel", "steps").third.dig("filterExpression", "andGroup", "expressions")
    expect(share.first).to eq("funnelEventFilter" => {"eventName" => "share"})
    expect(share.second.dig("funnelFieldFilter", "stringFilter", "value")).to eq(Google::Analytics::SyncService::HOSTNAME)
    expect(share.third.dig("orGroup", "expressions").map { |expression| expression.dig("funnelFieldFilter", "stringFilter", "value") })
      .to eq(%w[/post/ /tutorial/ /snippet/])

    resume = bodies.fourth.dig("funnel", "steps")
    expect(resume.map { |step| step["name"] }).to eq(["Visited the blog", "Downloaded the resume"])
    expect(resume.second.dig("filterExpression", "andGroup", "expressions").first)
      .to eq("funnelEventFilter" => {"eventName" => "download_resume"})
  end

  context "when no reader reached the later steps" do
    let(:steps) { [["1. Visited the blog", 5, 0, 5, 1]] }

    it "counts those steps as zero" do
      expect(funnels.funnels.first.steps.map(&:users)).to eq([5, 0, 0])
    end
  end

  it "says why when Analytics isn't configured" do
    result = funnels(property: "")

    expect(result.errors).to eq(["No Analytics property configured (credentials google.analytics_property_id)"])
  end
end
