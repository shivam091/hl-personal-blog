# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics funnels", type: :request do
  let(:service) { Google::Analytics::FunnelService }

  it "shows each funnel's steps with how many readers went on" do
    steps = [
      service::Step.new(
        name: "Visited the blog",
        users: 100,
        completion_rate: 0.4,
        abandonments: 60,
        abandonment_rate: 0.6
      ),
      service::Step.new(
        name: "Read an entry",
        users: 40,
        completion_rate: 0.05,
        abandonments: 38,
        abandonment_rate: 0.95
      ),
      service::Step.new(
        name: "Subscribed to the newsletter",
        users: 2,
        completion_rate: 0.0,
        abandonments: 0,
        abandonment_rate: 0.0
      )
    ]
    allow(service).to receive(:call) { service::Result.new(
      funnels: [
        service::Funnel.new(key: "newsletter", title: "Reading to subscribing", steps: steps)
      ],
      errors: [])
    }

    get google_analytics_funnels_path(compare: "off")

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML5(response.body)
    rows = page.css("#funnel-newsletter ~ div tbody tr").map { |row| row.css("td").map { |td| td.text.strip } }
    expect(rows).to eq([
      ["Visited the blog", "100", "40.0%", "60"],
      ["Read an entry", "40", "5.0%", "38"],
      ["Subscribed to the newsletter", "2", "—", "—"]
    ])
    expect(page.text).to include("2.0% of readers who visited went all the way.")
  end

  it "sets each step's readers against the compared period's" do
    funnel = ->(*users) {
      steps = users.map.with_index { |count, index| service::Step.new(name: "Step #{index + 1}", users: count) }
      service::Result.new(funnels: [service::Funnel.new(key: "newsletter", title: "Reading to subscribing", steps: steps)], errors: [])
    }
    allow(service).to receive(:call) do |period|
      (period.from == Date.new(2026, 10, 8)) ? funnel.(100, 40, 2) : funnel.(50, 40, 0)
    end

    get google_analytics_funnels_path(from: "2026-10-08", to: "2026-10-14")

    page = Nokogiri::HTML5(response.body)
    expect(page.css("#funnel-newsletter ~ div thead th").map { |th| th.text.strip }).not_to include("Change")
    changes = page.css("#funnel-newsletter ~ div tbody tr").map { |row| row.css("td")[1].css("span").text.strip }
    expect(changes).to eq(["(+100%)", "(0%)", "(new)"])
    expect(page.text).to include("2.0% of readers who visited went all the way, against 0.0% in")
  end

  it "keeps the period's funnels when the compared period can't be read" do
    allow(service).to receive(:call) do |period|
      next service::Result.new(funnels: [], errors: ["Analytics funnel “Reading to subscribing”: quota"]) unless period.from == Date.new(2026, 10, 8)

      service::Result.new(funnels: [service::Funnel.new(key: "newsletter", title: "Reading to subscribing",
        steps: [service::Step.new(name: "Visited the blog", users: 10)])], errors: [])
    end

    get google_analytics_funnels_path(from: "2026-10-08", to: "2026-10-14")

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#funnel-newsletter")).to be_present
    expect(page.at_css("[role=alert]").text).to include("Analytics funnel “Reading to subscribing”: quota")
  end

  it "says from when the share funnel's last step counts, while either period reaches back past it" do
    steps = [service::Step.new(name: "Visited the blog", users: 10), service::Step.new(name: "Shared the entry", users: 1)]
    allow(service).to receive(:call) do
      service::Result.new(funnels: [service::Funnel.new(key: "share", title: "Reading to sharing", steps: steps,
        counted_since: Date.new(2026, 10, 23), server_sent: false)], errors: [])
    end

    get google_analytics_funnels_path(from: "2026-10-01", to: "2026-10-23")
    expect(response.body).to include("The last step only counts from 23 Oct 2026")

    # Compared with 22 Oct, before shares were tracked.
    get google_analytics_funnels_path(from: "2026-10-23", to: "2026-10-23")
    expect(response.body).to include("The last step only counts from 23 Oct 2026")

    get google_analytics_funnels_path(from: "2026-10-23", to: "2026-10-23", compare: "off")
    expect(response.body).not_to include("The last step only counts from")
    # Shares are sent from the browser, so a blocked one has nothing counted elsewhere.
    expect(response.body).not_to include("browser blocks Analytics")
  end

  it "sets each segment's readers at every step beside the funnel's, when split" do
    steps = ->(*users) { users.map.with_index { |count, index| service::Step.new(name: "Step #{index + 1}", users: count) } }
    allow(service).to receive(:call) do |_period, breakdown:, **|
      service::Result.new(breakdown: breakdown, errors: [], funnels: [service::Funnel.new(key: "newsletter", title: "Reading to subscribing",
        steps: steps.(100, 40, 2), segments: [service::Segment.new(value: "IN", steps: steps.(60, 30, 2))])])
    end

    get google_analytics_funnels_path(breakdown: "country", compare: "off")

    page = Nokogiri::HTML5(response.body)
    expect(service).to have_received(:call).with(anything, breakdown: "country", next_action: nil, definitions: anything)
    segment = page.css("#funnel-newsletter ~ div table").last
    expect(segment.css("thead th").map { |th| th.text.strip }).to eq(["Country", "Step 1", "Step 2", "Step 3", "All the way"])
    expect(segment.css("tbody td").map { |td| td.text.strip }).to eq(["🇮🇳 IN", "60", "30", "2", "3.3%"])
  end

  it "exports every step, the whole funnel's and each segment's" do
    steps = ->(*users) { users.map.with_index { |count, index| service::Step.new(name: "Step #{index + 1}", users: count, completion_rate: 0.5, abandonments: 1) } }
    allow(service).to receive(:call) do |_period, breakdown:, **|
      service::Result.new(breakdown: breakdown, errors: [], funnels: [service::Funnel.new(key: "resume", title: "Resume",
        steps: steps.(10, 2), segments: [service::Segment.new(value: "mobile", steps: steps.(6, 1))])])
    end

    get google_analytics_funnels_path(format: :csv, breakdown: "device", from: "2026-10-01", to: "2026-10-07", compare: "off")

    expect(response.headers["Content-Disposition"]).to include("analytics-funnels-by-device-2026-10-01-to-2026-10-07.csv")
    expect(CSV.parse(response.body)).to eq([
      ["Funnel", "Segment", "Step number", "Step", "Readers", "Went on", "Dropped"],
      ["Resume", "All", "1", "Step 1", "10", "0.5", "1"],
      ["Resume", "All", "2", "Step 2", "2", nil, nil],
      ["Resume", "mobile", "1", "Step 1", "6", "0.5", "1"],
      ["Resume", "mobile", "2", "Step 2", "1", nil, nil]
    ])
  end

  it "shows where readers went after each step, and passes the pick to GA" do
    steps = [service::Step.new(name: "Visited the blog", users: 10), service::Step.new(name: "Downloaded the resume", users: 2)]
    allow(service).to receive(:call) do |_period, next_action:, **|
      service::Result.new(next_action: next_action, errors: [], funnels: [service::Funnel.new(key: "resume", title: "Resume", steps: steps,
        next_actions: [[["/about", 6], ["/post/rails", 3]], []])])
    end

    get google_analytics_funnels_path(next: "page", compare: "off")

    expect(service).to have_received(:call).with(anything, breakdown: nil, next_action: "page", definitions: anything)
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#funnel-next option[selected]")["value"]).to eq("page")
    table = page.css("table").find { |candidate| candidate.text.include?("Next page") }
    expect(table.css("tbody tr").map { |row| row.css("td").map { |td| td.text.strip } })
      .to eq([["Visited the blog", "/about", "6"], ["/post/rails", "3"], ["Downloaded the resume", "—", ""]])
  end

  it "charts each step's readers by day" do
    steps = [service::Step.new(name: "Visited the blog", users: 10), service::Step.new(name: "Downloaded the resume", users: 2)]
    allow(service).to receive(:call) do
      service::Result.new(errors: [], funnels: [service::Funnel.new(key: "resume", title: "Resume", steps: steps,
        trend: {Date.new(2026, 10, 1) => [6, 1], Date.new(2026, 10, 2) => [4, 1]})])
    end

    get google_analytics_funnels_path(from: "2026-10-01", to: "2026-10-02", compare: "off")

    expect(Nokogiri::HTML5(response.body).at_css("[aria-label^='Resume: readers at each step per day']")).to be_present
  end

  it "shows how many times a labelled step happened, and each kind's times and readers" do
    kinds = [service::Label.new(label: "LinkedIn", events: 32, users: 2), service::Label.new(label: "X (Twitter)", events: 24, users: 1)]
    steps = [
      service::Step.new(name: "Read an entry", users: 218, completion_rate: 0.01, abandonments: 215, abandonment_rate: 0.99),
      service::Step.new(name: "Shared the entry", users: 3, completion_rate: 0.0, abandonments: 0, abandonment_rate: 0.0, events: 56, labels: kinds)
    ]
    allow(service).to receive(:call) { service::Result.new(funnels: [service::Funnel.new(key: "share", title: "Reading to sharing", steps: steps)], errors: []) }

    get google_analytics_funnels_path(compare: "off")

    page = Nokogiri::HTML5(response.body)
    shared = page.css("#funnel-share ~ ol li").last
    expect(shared.at_css("div").text.squish).to eq("Shared the entry 3 · 56 times")
    expect(shared.css("table[aria-label='Shared the entry, by kind'] tbody tr").map { |row| row.css("td").map(&:text) })
      .to eq([["LinkedIn", "32", "2"], ["X (Twitter)", "24", "1"]])
    expect(page.css("#funnel-share ~ ol li").first.text).not_to include("times")
  end

  it "says why when Analytics can't be read" do
    allow(service).to receive(:call) do
      service::Result.new(
        funnels: [],
        errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
      )
    end

    get google_analytics_funnels_path

    expect(Nokogiri::HTML5(response.body).at_css("[role=alert]").text).to include("No Analytics property configured")
  end
end
