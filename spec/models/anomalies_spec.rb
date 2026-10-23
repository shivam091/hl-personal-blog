# encoding: UTF-8

require "rails_helper"

RSpec.describe Anomalies do
  let(:today) { Date.new(2026, 10, 12) }

  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  subject(:anomalies) { described_class.new(today: today) }

  before { RequestLog.delete_all }

  def titles
    anomalies.flags.map(&:title)
  end

  def views_on(counts)
    PageView.collection.insert_one("_id" => "/a", "slug" => "/a", "countriesByDay" => counts.transform_values { |count| {"IN" => count} })
  end

  it "flags nothing on an ordinary day" do
    views_on("2026-10-11" => 20, "2026-10-04" => 20, "2026-09-27" => 20, "2026-09-20" => 20, "2026-09-13" => 20)

    expect(anomalies).not_to be_any
  end

  it "flags views far above or below the same weekday's usual" do
    views_on("2026-10-11" => 90, "2026-10-04" => 20, "2026-09-27" => 20, "2026-09-20" => 20, "2026-09-13" => 20)
    expect(titles).to eq(["Views spiked yesterday"])
    expect(anomalies.flags.first.detail).to eq("90 views against a usual 20 on a Sunday.")
  end

  it "flags a drop in views, but not on a handful" do
    views_on("2026-10-11" => 5, "2026-10-04" => 20, "2026-09-27" => 20, "2026-09-20" => 20, "2026-09-13" => 20)
    expect(titles).to eq(["Views dropped yesterday"])

    PageView.delete_all
    views_on("2026-10-11" => 1, "2026-10-04" => 4, "2026-09-27" => 4)
    expect(described_class.new(today: today).flags).to be_empty
  end

  it "judges only by weeks since Google Analytics began, and not at all with too few" do
    views_on("2026-07-04" => 90, "2026-06-27" => 20, "2026-06-20" => 20, "2026-06-13" => 500)
    expect(described_class.new(today: Date.new(2026, 7, 5)).flags.first.detail).to eq("90 views against a usual 20 on a Saturday.")

    PageView.delete_all
    views_on("2026-07-01" => 90, "2026-06-24" => 20, "2026-06-17" => 500)
    expect(described_class.new(today: Date.new(2026, 7, 2)).flags).to be_empty
  end

  it "flags search clicks falling week on week, from the latest synced day" do
    (0..13).each do |back|
      Google::SearchConsole::Stat.create!(date: Date.new(2026, 10, 9) - back, clicks: back < 7 ? 1 : 10, impressions: 100, position: 5.0)
    end

    expect(titles).to eq(["Search clicks fell"])
    expect(anomalies.flags.first.detail).to eq("7 clicks in the week to 9 Oct, 2026, down from 70 the week before.")
  end

  def ai_days(first_week, second_week, last: Date.new(2026, 10, 8))
    ((last - 13)..last).each_with_index do |date, index|
      Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: date, impressions: index < 7 ? first_week : second_week)
    end
  end

  it "flags AI impressions falling or jumping between the latest two uploaded weeks, however long ago they end" do
    ai_days(10, 4)
    expect(titles).to eq(["AI impressions fell"])
    expect(anomalies.flags.first.detail).to eq("28 AI impressions in the week to #{I18n.l(Date.new(2026, 10, 8))}, against 70 the week before.")

    Google::SearchConsole::GenerativeAiStat.delete_all
    ai_days(5, 10)
    expect(described_class.new(today: today).flags.map(&:title)).to eq(["AI impressions jumped"])
  end

  it "leaves AI impressions alone with too few, or a week not wholly uploaded" do
    ai_days(2, 1)
    expect(titles).to be_empty

    Google::SearchConsole::GenerativeAiStat.delete_all
    ai_days(10, 4)
    Google::SearchConsole::GenerativeAiStat.where(date: Date.new(2026, 9, 28)).delete_all
    expect(described_class.new(today: today).flags.map(&:title)).to be_empty
  end

  it "flags a sync whose last runs all failed" do
    2.times { |run| SyncRequest.create!(kind: "crux", status: "failed", finished_at: run.hours.ago) }
    SyncRequest.create!(kind: "feed", status: "failed", finished_at: 1.hour.ago)
    SyncRequest.create!(kind: "feed", status: "succeeded", finished_at: 2.hours.ago)

    expect(titles).to eq(["Web Vitals history sync keeps failing"])
  end

  it "flags a failing service, server errors and unsafe links" do
    10.times { |n| ExternalCall.create!(service: "Search Console", http_method: "GET", url: "https://example.com/", status: n < 3 ? 500 : 200) }
    RequestLog.create!(uri: "https://admin.example.com/", request_method: "GET", status: 500)
    RequestLog.create!(uri: "http://localhost:3000/", request_method: "GET", status: 500)
    Google::SafeBrowsing::LinkCheck.create!(url: "https://bad.example.com/", threat_types: ["MALWARE"])

    expect(titles).to eq(["Search Console is failing", "Server errors", "Unsafe outbound links"])
    expect(anomalies.flags.second.detail).to eq("1 request failed with a 5xx status in the last 24 hours.")
  end

  describe "consent flags" do
    let(:usual) { {ga_ratio: 0.8, loaded_share: 0.9, banner_per_pending: 1.0, shown: 40, no_answer: 10, first_party: 200} }

    def settled(days: 6, **attributes)
      days.times { |n| ConsentSnapshot.create!(usual.merge(attributes).merge(day: (Date.new(2026, 10, 5) + n).iso8601)) }
    end

    def yesterday(**attributes)
      ConsentSnapshot.create!(usual.merge(attributes).merge(day: "2026-10-11"))
    end

    it "flags nothing on an ordinary day" do
      settled
      yesterday(ga_ratio: 0.75, loaded_share: 0.85, no_answer: 14)

      expect(titles).to be_empty
    end

    it "says nothing without enough settled days to call anything usual" do
      settled(days: 4)
      yesterday(ga_ratio: 0.2)

      expect(titles).to be_empty
    end

    it "flags GA suddenly missing more of our views" do
      settled
      yesterday(ga_ratio: 0.5)

      expect(titles).to eq(["GA is missing more views than usual"])
      expect(anomalies.flags.first.detail).to eq("GA counted 50% of our views yesterday, against a usual 80%.")
      expect(anomalies.flags.first.path.last).to eq(from: "2026-10-11", to: "2026-10-11")
    end

    it "flags the tag loading for fewer readers" do
      settled
      yesterday(loaded_share: 0.6)

      expect(titles).to eq(["The GA tag is loading less often"])
    end

    it "flags the banner showing far less for the readers it should ask" do
      settled
      yesterday(banner_per_pending: 0.2, shown: 10)

      expect(titles).to eq(["The cookie banner is showing less"])
    end

    it "flags a jump in banners left unanswered, but not on a handful of banners" do
      settled
      yesterday(no_answer: 38)
      expect(titles).to eq(["More banners are going unanswered"])

      ConsentSnapshot.where(day: "2026-10-11").delete_all
      yesterday(shown: 10, no_answer: 10)
      expect(described_class.new(today: today).flags.map(&:title)).to be_empty
    end

    it "judges a day not snapshotted yet from the live data" do
      settled
      PageView.collection.insert_one("_id" => "/a", "slug" => "/a", "countriesByDay" => {"2026-10-11" => {"IN" => 100}},
        "consentByDay" => {"2026-10-11" => {"granted" => 100}})
      Google::Analytics::Stat.create!(date: Date.new(2026, 10, 11), page_path: "/a", views: 40)

      expect(titles).to include("GA is missing more views than usual")
    end
  end
end
