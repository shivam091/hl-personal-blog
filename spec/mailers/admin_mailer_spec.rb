# encoding: UTF-8

require "rails_helper"

RSpec.describe AdminMailer, type: :mailer do
  # So specs don't depend on whatever the local credentials hold (CI has none).
  before do
    ActionMailer::Base.deliveries.clear
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :from) { "Blog <blog@domain.com>" }
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :notify_to) { "me@domain.com" }
  end

  describe "#launch_report" do
    it "sets each measure beside the typical entry's, linking to the page in the admin" do
      entry = FeedEntry.create!(url: "https://blog.example.com/post/new/", name: "New <post>", type: "post",
        published_at: Time.zone.parse("2026-10-13 09:00"), last_modified_at: Time.zone.parse("2026-10-13 09:00"))
      report = LaunchReport.new(entry, 7, today: Date.new(2026, 10, 20))
      allow(report).to receive(:measures) do
        [LaunchReport::Measure.new(label: "Views", value: 60, typical: 20, settled: true),
         LaunchReport::Measure.new(label: "Search clicks", value: 4, typical: nil, settled: false)]
      end

      message = described_class.launch_report(report).message
      html = message.html_part.body.to_s
      text = message.text_part.body.to_s

      expect(ActionMailer::Base.deliveries).to eq([message])
      expect(message.to).to eq(["me@domain.com"])
      expect(message.subject).to eq("Day 7: New <post> is ahead of the typical entry")
      expect(html).to include("New &lt;post&gt;", "300%", "(so far)", 'href="http://example.com/page-views/%2Fpost%2Fnew"')
      expect(text).to include("- Views: 60, typical 20", "- Search clicks: 4 (so far), typical unknown")
    end
  end

  describe "#launch_report's GA share" do
    let(:entry) do
      FeedEntry.create!(url: "https://blog.example.com/post/new/", name: "New post", type: "post",
        published_at: Time.zone.parse("2026-10-13 09:00"), last_modified_at: Time.zone.parse("2026-10-13 09:00"))
    end

    def message_for(share)
      report = LaunchReport.new(entry, 7, today: Date.new(2026, 10, 20))
      allow(report).to receive_messages(measures: [LaunchReport::Measure.new(label: "Views", value: 60, typical: 20, settled: true),
        LaunchReport::Measure.new(label: "Analytics views", value: 24, typical: 30, settled: true)], ga_share: share)
      described_class.launch_report(report).message
    end

    it "sits beside Analytics views, so a low GA figure isn't read as a weak entry" do
      message = message_for(0.4)

      expect(message.html_part.body.to_s).to include("share of its views: 40%")
      expect(message.text_part.body.to_s).to include("- Analytics views: 24, typical 30\n  GA's share of its views: 40%")
    end

    it "shows a dash when it can't be told" do
      expect(message_for(nil).text_part.body.to_s).to include("GA's share of its views: —")
    end

    it "is worked out from the entry's own views over the same days" do
      PageView.collection.insert_one("_id" => "/post/new", "slug" => "/post/new", "countriesByDay" => {"2026-10-14" => {"IN" => 50}})
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 14), page_path: "/post/new/", views: 25)

      expect(LaunchReport.new(entry, 7, today: Date.new(2026, 10, 20)).ga_share).to eq(0.5)
    end
  end

  describe "#attention" do
    it "lists every item, each linking back to where to look in the admin" do
      anomalies = instance_double(Anomalies, flags: [
        Anomalies::Flag.new(level: :warning, icon: "search", title: "Search clicks fell", detail: "10 clicks, down from 40.",
          path: [:search_insight_report_path, {from: "2026-10-01", to: "2026-10-07"}]),
        Anomalies::Flag.new(level: :warning, icon: "alert-triangle", title: "Server errors", detail: "2 requests failed.",
          path: [:request_report_path, {}])
      ])

      message = described_class.attention(anomalies).message

      expect(message.subject).to eq("Needs attention: 2 things need attention")
      expect(message.html_part.body.to_s).to include("Search clicks fell", 'href="http://example.com/reports/search-insights?from=2026-10-01&amp;to=2026-10-07"',
        'href="http://example.com/monitoring/requests"')
      expect(message.text_part.body.to_s).to include("- Server errors: 2 requests failed.", "  http://example.com/monitoring/requests")
    end

    it "names the one item in the subject when there's only one" do
      anomalies = instance_double(Anomalies, flags: [
        Anomalies::Flag.new(level: :info, icon: "trending-up", title: "Views spiked yesterday", detail: "90 views.", path: [:page_views_path, {}])
      ])

      expect(described_class.attention(anomalies).message.subject).to eq("Needs attention: Views spiked yesterday")
    end
  end
end
