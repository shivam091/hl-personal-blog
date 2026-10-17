# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::PageFlowService do
  let(:report_url) { "https://analyticsdata.googleapis.com/v1beta/properties/123456789:runReport" }
  let(:funnel_url) { "https://analyticsdata.googleapis.com/v1alpha/properties/123456789:runFunnelReport" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:period) { Period.new({from: "2026-10-01", to: "2026-10-12"}, today: Date.new(2026, 10, 12)) }
  let(:bodies) { {} }
  let(:host) { Google::Analytics::SyncService::HOSTNAME }

  def flow(property: 123456789)
    described_class.new(property: property, client: google_client, cache: cache).call(period, path: "/post/rails")
  end

  before do
    google_stubs.post(report_url) do |env|
      bodies[:previous] = JSON.parse(env.body)
      referrers = [["https://#{host}/", 20], ["https://#{host}/?ref=nav", 4], ["https://www.google.com/", 15], ["", 6]]
      [200, {}, {
        rows: referrers.map { |referrer, views| {dimensionValues: [{value: referrer}], metricValues: [{value: views.to_s}, {value: "1"}]} },
        totals: [{dimensionValues: [{value: "RESERVED_TOTAL"}], metricValues: [{value: "45"}, {value: "30"}]}]
      }.to_json]
    end
    google_stubs.post(funnel_url) do |env|
      bodies[:next] = JSON.parse(env.body)
      [200, {}, {
        funnelVisualization: {
          dimensionHeaders: [{name: "funnelStepName"}, {name: "funnelStepNextAction"}],
          metricHeaders: [{name: "activeUsers"}],
          rows: [["/about", 3], ["/post/ruby", 6], ["/post/ruby?ref=related", 2]].map do |path, users|
            {dimensionValues: [{value: "1. Viewed /post/rails"}, {value: path}], metricValues: [{value: users.to_s}]}
          end
        }
      }.to_json]
    end
  end

  it "folds the blog's own referrers into its pages and other sites into their hosts" do
    result = flow.flow

    filters = bodies[:previous].dig("dimensionFilter", "andGroup", "expressions").map { |expression| expression["filter"] }
    expect(filters.map { |filter| [filter["fieldName"], filter.dig("stringFilter", "value")] }).to eq([["hostName", host], ["pagePath", "/post/rails"]])
    expect([result.views, result.readers]).to eq([45, 30])
    expect(result.previous.map { |source| [source.value, source.kind, source.views] })
      .to eq([["/", :page, 24], ["google.com", :site, 15], ["No referrer", :none, 6]])
  end

  it "follows readers on as a one-step funnel, most readers first" do
    result = flow.flow

    expect(bodies[:next]["funnelNextAction"]).to eq("nextActionDimension" => {"name" => "pagePathPlusQueryString"}, "limit" => 5)
    step = bodies[:next].dig("funnel", "steps").sole.dig("filterExpression", "andGroup", "expressions")
    expect(step.first).to eq("funnelEventFilter" => {"eventName" => "page_view"})
    expect(step.third.dig("funnelFieldFilter", "stringFilter", "value")).to eq("/post/rails(\\?.*)?")
    expect(result.next_pages).to eq([["/post/ruby", 8], ["/about", 3]])
  end

  it "reads a pasted link as its path" do
    expect(described_class.path("https://#{host}/post/rails?ref=x")).to eq("/post/rails")
    expect(described_class.path("not a path")).to be_nil
  end

  it "says why when Analytics isn't configured" do
    expect(flow(property: "").errors).to eq(["No Analytics property configured (credentials google.analytics_property_id)"])
  end
end
