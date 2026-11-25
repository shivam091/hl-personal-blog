# encoding: UTF-8

require "rails_helper"

RSpec.describe "Mixpanel's app and query APIs" do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:requests) { [] }

  def client
    connection = Faraday.new(url: "https://mixpanel.com") do |faraday|
      faraday.response :raise_error
      faraday.adapter :test, stubs
    end
    Mixpanel::Client.new(project_id: "123", username: "sa", secret: "secret", connection: connection, app_connection: connection)
  end

  describe Mixpanel::AnnotationService do
    let(:today) { Date.new(2026, 11, 25) }

    before do
      FeedEntry.create!(_id: "https://blog.example.com/post/a", name: "Grid", type: "post", published_at: Time.zone.parse("2026-11-20 09:30"), last_modified_at: Time.zone.parse("2026-11-20 09:30"))
      FeedEntry.create!(_id: "https://blog.example.com/post/b", name: "Flexbox", type: "post", published_at: Time.zone.parse("2026-11-22 18:00"), last_modified_at: Time.zone.parse("2026-11-22 18:00"))
      FeedEntry.create!(_id: "https://blog.example.com/post/old", name: "Old", type: "post", published_at: Time.zone.parse("2026-09-01 10:00"), last_modified_at: Time.zone.parse("2026-09-01 10:00"))
    end

    it "marks each recent post once, skipping those already marked" do
      stubs.get("/api/app/projects/123/annotations") do |env|
        requests << env.params
        [200, {}, {status: "ok", results: [{id: 1, date: "2026-11-20 09:30:00", description: "Published: Grid"}]}.to_json]
      end
      stubs.post("/api/app/projects/123/annotations") do |env|
        requests << JSON.parse(env.body)
        [201, {}, {status: "ok", results: {id: 2}}.to_json]
      end

      result = described_class.call(client: client, today: today)
      expect(result.summary).to eq("1 created, 0 updated, 1 unchanged, 0 failed")
      expect(requests.first).to eq("fromDate" => "2026-10-27", "toDate" => "2026-11-25")
      expect(requests.last).to eq("date" => "2026-11-22 18:00:00", "description" => "Published: Flexbox", "tags" => [])
    end

    it "reports a refusal" do
      stubs.get("/api/app/projects/123/annotations") { [403, {}, {error: "Permission denied"}.to_json] }

      expect(described_class.call(client: client, today: today).errors).to eq(["Mixpanel annotations: Permission denied"])
    end
  end

  describe Mixpanel::LexiconService do
    it "sends every planned event and the subscriber profile, without clearing the dictionary" do
      stubs.post("/api/app/projects/123/schemas") do |env|
        requests << JSON.parse(env.body)
        [200, {}, {status: "ok", results: {added: 40, deleted: 0}}.to_json]
      end

      expect(described_class.call(client: client).summary).to eq("0 created, 40 updated, 0 unchanged, 0 failed")
      body = requests.first
      expect(body["truncate"]).to be(false)
      leave = body["entries"].find { |entry| entry["name"] == "page_leave" }
      expect(leave["entityType"]).to eq("event")
      expect(leave.dig("schemaJson", "properties", "engaged_seconds")).to eq("type" => "integer",
        "description" => "Seconds the tab was visible and the reader active within the last 30 seconds.")
      expect(leave.dig("schemaJson", "properties")).to include("ga_status")
      subscribe = body["entries"].find { |entry| entry["name"] == "newsletter_subscribe" }
      expect(subscribe.dig("schemaJson", "properties").keys).to eq(["source"])
      expect(body["entries"].last).to include("entityType" => "profile", "name" => "$user")
    end
  end

  describe Mixpanel::RetentionService do
    it "stores each weekly cohort of new readers and how many came back" do
      stubs.get("/api/query/retention") do |env|
        requests << env.params
        [200, {}, {"2026-11-02" => {counts: [10, 3, 1], first: 10}, "2026-11-09" => {counts: [8, 2], first: 8}}.to_json]
      end

      result = described_class.call(client: client, today: Date.new(2026, 11, 25))
      expect(result.summary).to eq("2 created, 0 updated, 0 unchanged, 0 failed")
      expect(requests.first).to include("project_id" => "123", "from_date" => "2026-10-01", "to_date" => "2026-11-25",
        "retention_type" => "birth", "born_event" => "$mp_web_page_view", "unit" => "week", "interval_count" => "8")
      cohort = Mixpanel::RetentionCohort.find_by(cohort_date: Date.new(2026, 11, 2))
      expect(cohort.retention(1)).to eq(0.3)
      expect(cohort.retention(5)).to be_nil

      expect(described_class.call(client: client, today: Date.new(2026, 11, 25)).summary).to eq("0 created, 0 updated, 2 unchanged, 0 failed")
    end
  end
end
