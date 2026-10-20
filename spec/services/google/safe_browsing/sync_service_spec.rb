# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SafeBrowsing::SyncService do
  let(:url) { "https://safebrowsing.googleapis.com/v4/threatMatches:find" }
  let(:requests) { [] }

  def clicked(link)
    Google::Analytics::OutboundLinkStat.create!(
      date: Date.new(2026, 10, 10),
      page_path: "/post",
      link_url: link,
      event_count: 1
    )
  end

  def stub_matches(*matches)
    google_stubs.post(url) do |env|
      requests << JSON.parse(env.body)
      [200, {}, (matches.any? ? {matches: matches.map { |link, type| {threatType: type, threat: {url: link}} }} : {}).to_json]
    end
  end

  def sync
    described_class.call(client: google_key_client)
  end

  before do
    clicked("https://github.com/x")
    clicked("http://bad.example/")
    clicked("(not set)")
  end

  it "checks every clicked link, marking the ones Google lists as unsafe" do
    stub_matches(["http://bad.example/", "SOCIAL_ENGINEERING"], ["http://bad.example/", "MALWARE"])

    expect(sync.summary).to eq("2 created, 0 updated, 0 unchanged, 0 failed")
    expect(requests.first.dig("threatInfo", "threatEntries")).to eq([
      {"url" => "http://bad.example/"},
      {"url" => "https://github.com/x"}
    ])

    bad = Google::SafeBrowsing::LinkCheck.find_by(url: "http://bad.example/")

    expect(bad.threat_types).to eq(%w[MALWARE SOCIAL_ENGINEERING])
    expect(bad.threat_labels).to eq(["Malware", "Phishing or deception"])
    expect(bad.flagged_at).to be_present
    expect(Google::SafeBrowsing::LinkCheck.find_by(url: "https://github.com/x")).not_to be_flagged
  end

  it "keeps when a link was first flagged, and clears it once Google drops the link" do
    first = 3.days.ago.change(usec: 0)

    Google::SafeBrowsing::LinkCheck.create!(
      url: "http://bad.example/",
      threat_types: ["MALWARE"],
      flagged_at: first
    )
    Google::SafeBrowsing::LinkCheck.create!(
      url: "https://github.com/x",
      threat_types: ["MALWARE"],
      flagged_at: first
    )

    stub_matches(["http://bad.example/", "MALWARE"])

    expect(sync.summary).to eq("0 created, 1 updated, 1 unchanged, 0 failed")
    expect(Google::SafeBrowsing::LinkCheck.find_by(url: "http://bad.example/").flagged_at).to eq(first)
    expect(Google::SafeBrowsing::LinkCheck.find_by(url: "https://github.com/x")).to have_attributes(
      threat_types: [], flagged_at: nil
    )
  end

  it "reports a refused key" do
    google_stubs.post(url) { [400, {}, {error: {message: "API key not valid."}}.to_json] }

    expect(sync.errors).to eq(["Safe Browsing: API key not valid."])
  end
end
