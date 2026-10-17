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
    expect(page.css("#funnel-newsletter ~ div thead th").map { |th| th.text.strip }.last).to eq("Change")
    changes = page.css("#funnel-newsletter ~ div tbody tr").map { |row| row.css("td").last.text.strip }
    expect(changes).to eq(["100.0%", "No change", "No earlier data"])
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
      service::Result.new(funnels: [service::Funnel.new(key: "share", title: "Reading to sharing", steps: steps)], errors: [])
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
