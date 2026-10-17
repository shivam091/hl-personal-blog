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

  let(:report) { table(*steps) }

  def funnels(property: 123456789)
    described_class.new(property: property, client: google_client, cache: cache).call(period)
  end

  before do
    google_stubs.post(url) do |env|
      bodies << JSON.parse(env.body)
      [200, {}, report.to_json]
    end
  end

  it "reads each funnel's steps in order, with GA's completion and abandonment" do
    result = funnels

    expect(result.errors).to eq([])
    newsletter = result.funnels.first
    expect(newsletter.steps.map(&:to_h)).to eq([
      {name: "Visited the blog", users: 100, completion_rate: 0.4, abandonments: 60, abandonment_rate: 0.6, events: nil, labels: nil},
      {name: "Read an entry", users: 40, completion_rate: 0.05, abandonments: 38, abandonment_rate: 0.95, events: nil, labels: nil},
      {name: "Subscribed to the newsletter", users: 2, completion_rate: 0.0, abandonments: 0, abandonment_rate: 0.0, events: nil, labels: nil}
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
    expect(entry_filters.map { |filter| filter.dig("stringFilter", "value") }).to eq(%w[/post/ /tutorial/ /snippet/ /series/])
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

  it "counts shares made from entries on the live site, and resume downloads from any page" do
    funnels

    share = bodies.third.dig("funnel", "steps").third.dig("filterExpression", "andGroup", "expressions")
    expect(share.first).to eq("funnelEventFilter" => {"eventName" => "share"})
    expect(share.second.dig("funnelFieldFilter", "stringFilter", "value")).to eq(Blog.host)
    expect(share.third.dig("orGroup", "expressions").map { |expression| expression.dig("funnelFieldFilter", "stringFilter", "value") })
      .to eq(%w[/post/ /tutorial/ /snippet/ /series/])

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

  it "seeds the blog's four funnels when none are stored, and reads them back in order" do
    funnels

    expect(Google::Analytics::FunnelDefinition.ordered.pluck(:key)).to eq(%w[newsletter contact share resume])
    expect(funnels.funnels.map(&:key)).to eq(%w[newsletter contact share resume])
    expect(funnels.funnels.first.server_sent).to be(true)
  end

  it "asks GA again once a funnel is edited" do
    funnels
    Google::Analytics::FunnelDefinition.find_by(key: "resume").update!(title: "Resume downloads")
    funnels

    expect(bodies.size).to eq(5)
  end

  context "with the trended view" do
    let(:report) do
      table(*steps).merge(funnelVisualization: {
        dimensionHeaders: [{name: "date"}, {name: "funnelStepName"}],
        metricHeaders: [{name: "activeUsers"}],
        rows: [["20261002", "1. Visited the blog", 7], ["20261001", "1. Visited the blog", 5], ["20261001", "2. Read an entry", 2]]
          .map { |date, name, users| {dimensionValues: [{value: date}, {value: name}], metricValues: [{value: users.to_s}]} }
      })
    end

    it "asks for it with the funnel and reads each day's readers at every step" do
      newsletter = funnels.funnels.first

      expect(bodies.first["funnelVisualizationType"]).to eq("TRENDED_FUNNEL")
      expect(newsletter.trend).to eq(Date.new(2026, 10, 1) => [5, 2, 0], Date.new(2026, 10, 2) => [7, 0, 0])
    end
  end

  context "with a next action picked" do
    let(:report) do
      table(*steps).merge(funnelVisualization: {
        dimensionHeaders: [{name: "funnelStepName"}, {name: "funnelStepNextAction"}],
        metricHeaders: [{name: "activeUsers"}],
        rows: [["1. Visited the blog", "/about", 3], ["1. Visited the blog", "/post/rails", 7], ["1. Visited the blog", "/post/rails?ref=nav", 2],
          ["2. Read an entry", "(not set)", 4]]
          .map { |name, value, users| {dimensionValues: [{value: name}, {value: value}], metricValues: [{value: users.to_s}]} }
      })
    end

    it "asks GA apart for each step's next page, folding query strings into the path, most readers first" do
      result = described_class.new(property: 123456789, client: google_client, cache: cache).call(period, next_action: "page")

      expect(result.next_action).to eq("page")
      expect(bodies.second["funnelNextAction"]).to eq("nextActionDimension" => {"name" => "pagePathPlusQueryString"}, "limit" => 5)
      expect(bodies.second["funnelVisualizationType"]).to eq("STANDARD_FUNNEL")
      expect(result.funnels.first.next_actions).to eq([[["/post/rails", 9], ["/about", 3]], [["(not set)", 4]], []])
    end

    it "asks only once per funnel when none is picked" do
      funnels

      expect(bodies.size).to eq(4)
      expect(bodies).to all(satisfy { |body| !body.key?("funnelNextAction") })
    end
  end

  context "when split by device" do
    let(:report) do
      rows = [["1. Visited the blog", "RESERVED_TOTAL", 100], ["2. Read an entry", "RESERVED_TOTAL", 40],
        ["1. Visited the blog", "desktop", 30], ["2. Read an entry", "desktop", 20],
        ["1. Visited the blog", "mobile", 70], ["2. Read an entry", "mobile", 20]]
      table.tap do |split|
        split[:funnelTable][:dimensionHeaders] << {name: "deviceCategory"}
        split[:funnelTable][:rows] = rows.map do |name, device, users|
          {dimensionValues: [{value: name}, {value: device}], metricValues: [{value: users.to_s}, {value: "0"}, {value: "0"}, {value: "0"}]}
        end
      end
    end

    it "asks GA for the split and reads each device's steps apart from the totals, most readers first" do
      newsletter = described_class.new(property: 123456789, client: google_client, cache: cache).call(period, breakdown: "device").funnels.first

      expect(bodies.first["funnelBreakdown"]).to eq("breakdownDimension" => {"name" => "deviceCategory"}, "limit" => 10)
      expect(newsletter.steps.map(&:users)).to eq([100, 40, 0])
      expect(newsletter.segments.map { |segment| [segment.value, segment.steps.map(&:users)] })
        .to eq([["mobile", [70, 20, 0]], ["desktop", [30, 20, 0]]])
    end

    it "asks GA for any of the other splits by its own dimension" do
      described_class.new(property: 123456789, client: google_client, cache: cache).call(period, breakdown: "channel")

      expect(bodies.first["funnelBreakdown"]).to eq("breakdownDimension" => {"name" => "sessionDefaultChannelGroup"}, "limit" => 10)
    end

    it "reads an unknown split as none" do
      result = described_class.new(property: 123456789, client: google_client, cache: cache).call(period, breakdown: "planet")

      expect(result.breakdown).to be_nil
      expect(bodies.first).not_to have_key("funnelBreakdown")
    end
  end

  context "with a step whose event the blog labels by kind" do
    let(:label_url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport" }
    let(:label_bodies) { [] }

    def label_report(rows, total_events:, total_users:)
      {
        dimensionHeaders: [{name: "customEvent:event_label"}],
        metricHeaders: [{name: "eventCount"}, {name: "activeUsers"}],
        rows: rows.map { |label, events, users| {dimensionValues: [{value: label}], metricValues: [{value: events.to_s}, {value: users.to_s}]} },
        totals: [{dimensionValues: [{value: "RESERVED_TOTAL"}], metricValues: [{value: total_events.to_s}, {value: total_users.to_s}]}]
      }
    end

    before do
      Google::Analytics::EventLabelStat.create!(date: Date.new(2026, 10, 5), page_path: "/post/a", event_name: "share",
        event_label: "LinkedIn", event_count: 1)
      google_stubs.post(label_url) do |env|
        label_bodies << JSON.parse(env.body)
        [200, {}, label_report([["LinkedIn", 32, 2], ["Facebook", 26, 2], ["(not set)", 2, 1]], total_events: 60, total_users: 3).to_json]
      end
    end

    it "counts the step's times, and each kind's times and readers, most times first" do
      share = funnels.funnels.find { |funnel| funnel.key == "share" }

      shared = share.steps.last
      expect(shared.events).to eq(60)
      expect(shared.labels.map(&:to_h)).to eq([
        {label: "LinkedIn", events: 32, users: 2}, {label: "Facebook", events: 26, users: 2}, {label: "No label", events: 2, users: 1}
      ])
      expect(share.steps.first(2).map(&:events)).to eq([nil, nil])
      expect(share.steps.first.labels).to eq([])
    end

    it "leaves a step alone whose event only now and then carries a label" do
      Google::Analytics::EventLabelStat.create!(date: Date.new(2026, 10, 5), page_path: "/", event_name: "session_start",
        event_label: "/", event_count: 2)
      Google::Analytics::EventStat.create!(date: Date.new(2026, 10, 5), page_path: "/", event_name: "session_start", event_count: 100)

      share = funnels.funnels.find { |funnel| funnel.key == "share" }

      expect(share.steps.first.events).to be_nil
      expect(label_bodies.map { |body| body.dig("dimensionFilter", "andGroup", "expressions", 0, "filter", "stringFilter", "value") }.uniq)
        .to eq(["share"])
    end

    it "asks GA only for the labelled step, on the same events the funnel counts" do
      funnels

      expect(label_bodies.size).to eq(1)
      body = label_bodies.first
      expect(body["dateRanges"]).to eq([{"startDate" => "2026-10-01", "endDate" => "2026-10-12"}])
      expect(body["dimensions"]).to eq([{"name" => "customEvent:event_label"}])
      expect(body["metricAggregations"]).to eq(["TOTAL"])
      conditions = body.dig("dimensionFilter", "andGroup", "expressions")
      expect(conditions.first.dig("filter", "fieldName")).to eq("eventName")
      expect(conditions.first.dig("filter", "stringFilter", "value")).to eq("share")
      expect(conditions.second.dig("filter", "stringFilter", "value")).to eq(Blog.host)
      expect(conditions.third.dig("orGroup", "expressions").map { |condition| condition.dig("filter", "stringFilter", "value") })
        .to eq(%w[/post/ /tutorial/ /snippet/ /series/])
    end
  end

  it "says why when Analytics isn't configured" do
    result = funnels(property: "")

    expect(result.errors).to eq(["No Analytics property configured (credentials google.analytics_property_id)"])
  end
end
