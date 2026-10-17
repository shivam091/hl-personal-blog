# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics acquisition", type: :request do
  let(:yesterday) { Date.new(2026, 10, 12) }

  # The day after, so the default period, which ends yesterday, covers the
  # day the figures are stored for.
  around { |example| travel_to((yesterday + 1).in_time_zone.change(hour: 12)) { example.run } }

  def table_rows
    Nokogiri::HTML5(response.body).css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.drop(1) }
  end

  def page_headings
    Nokogiri::HTML5(response.body).css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }.drop(2)
  end

  it "shows the user acquisition breakdown at the bare path" do
    get google_analytics_acquisition_path

    expect(response).to have_http_status(:ok)
    expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breakdown] a[aria-current=page]").text).to eq("User acquisition")
  end

  it "lays the figures out as saved, the breakdown's own columns standing where it puts them" do
    Google::Analytics::SourceStat.create!(date: yesterday, page_path: "/post/a", channel_group: "Direct", source: "(direct)", medium: "(none)", views: 9, sessions: 1)
    Google::Analytics::SourceStat.create!(date: yesterday, page_path: "/post/b", channel_group: "Organic Search", source: "google", medium: "organic", views: 2, sessions: 5)
    layout = ListLayout.find(:analytics_acquisition)
    hidden = layout.columns.map(&:key) - %w[sessions breakdown views total_users]
    ListSetting.create!(list: "analytics_acquisition", order: %w[sessions breakdown total_users views], hidden: hidden,
      sort: "sessions", direction: "asc", row_numbers: false)

    get google_analytics_acquisition_breakdown_path("sources")

    page = Nokogiri::HTML5(response.body)
    expect(headings).to eq(%w[Sessions Channel Source Medium Views])
    expect(page.css("tbody tr").map { |row| row.css("td").map { |cell| cell.text.squish }.compact_blank.first(2) })
      .to eq([["1 (16.67%)", "Direct"], ["5 (83.33%)", "Organic Search"]])
    expect(page.at_css("a[href='#{edit_list_layout_path("analytics_acquisition")}']")).to be_present

    ListSetting.delete_all
    get google_analytics_acquisition_breakdown_path("sources")

    expect(headings.first(5)).to eq(["#", "Channel", "Source", "Medium", "Views"])
  end

  # Every heading, with no row numbers to drop.
  def headings
    Nokogiri::HTML5(response.body).css("thead tr").first.css("th").map { |cell| (cell.at_css("a") || cell).text.squish }.compact_blank
  end

  it "explains every tile in a tooltip tied to its help button" do
    get google_analytics_acquisition_breakdown_path("sources")

    page = Nokogiri::HTML5(response.body)
    buttons = page.css("dl button[aria-describedby]")
    expect(buttons.map { |button| button["aria-label"] }).to eq(["About Views", "About Active users", "About Views per active user",
      "About New users", "About Sessions", "About Engaged sessions", "About Engagement rate", "About Engaged sessions per active user",
      "About Engagement per user", "About Events per session", "About Event count", "About Key events"])
    expect(page.at_css("##{buttons.first["aria-describedby"]}[role=tooltip]").text.strip)
      .to eq("The number of web pages your users saw. Repeated views of a single page are counted.")
  end

  it "charts each week's sessions split by channel on the sources breakdown only" do
    Google::Analytics::SourceStat.create!(
      date: yesterday,
      page_path: "/post/a",
      channel_group: "Organic Search",
      source: "google",
      medium: "organic",
      sessions: 6
    )
    Google::Analytics::SourceStat.create!(
      date: yesterday,
      page_path: "/post/b",
      channel_group: "Direct",
      source: "(direct)",
      medium: "(none)",
      sessions: 2
    )

    get google_analytics_acquisition_breakdown_path("sources")

    card = Nokogiri::HTML5(response.body).at_css("#channel-mix").parent
    expect(card.css("ul li").map(&:text)).to eq(["Organic Search", "Direct", "Other"])
    expect(JSON.parse(card.css("rect[data-tip]").last["data-tip"])["rows"].map { |row| row["name"] })
      .to eq(["Organic Search", "Direct", "Other"])

    get google_analytics_acquisition_breakdown_path("referrers")

    expect(Nokogiri::HTML5(response.body).at_css("#channel-mix")).to be_nil
  end

  it "splits sources by channel, source and medium, searchable by source" do
    Google::Analytics::SourceStat.create!(date: yesterday, page_path: "/post/a", channel_group: "Organic Search", source: "google", medium: "organic", views: 7)
    Google::Analytics::SourceStat.create!(date: yesterday, page_path: "/post/b", channel_group: "Organic Search", source: "google", medium: "organic", views: 3)
    Google::Analytics::SourceStat.create!(date: yesterday, page_path: "/post/a", channel_group: "Referral", source: "reddit.com", medium: "referral", views: 1)

    get google_analytics_acquisition_breakdown_path("sources", source: "goo")

    expect(table_rows.map { |row| row.first(5) }).to eq([["1", "Organic Search", "google", "organic", "10 (100%)"]])
  end

  it "charts views over time for the leading rows, with a Total row each figure is a share of" do
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/post/a", referrer: "reddit.com", views: 3, active_users: 1)
    Google::Analytics::ReferrerStat.create!(date: yesterday - 1, page_path: "/post/b", referrer: "t.co", views: 1, active_users: 1)

    get google_analytics_acquisition_breakdown_path("referrers")

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("#chart-over-time").text.squish).to eq("Views by referrer over time")
    expect(page.css("section[aria-labelledby=chart-ranking] li span[title]").map(&:text)).to eq(%w[reddit.com t.co])
    expect(page.at_css("thead tr:last-child").text.squish).to start_with("Total 4 100% of total")
  end

  it "lists only tagged campaigns, asking GA to leave out its untagged ones too" do
    Google::Analytics::CampaignStat.create!(date: yesterday, page_path: "/post/a", campaign: "new_entry", source: "newsletter", medium: "email",
      content: "button", views: 4)
    Google::Analytics::CampaignStat.create!(date: yesterday, page_path: "/post/a", campaign: "(organic)", source: "google", medium: "organic",
      content: "(not set)", views: 9)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_acquisition_breakdown_path("campaigns")

    expect(table_rows.map { |row| row.first(6) }).to eq([["1", "new_entry", "newsletter", "email", "button", "4 (100%)"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(filters: include(["sessionCampaignName", "EXACT", "(direct)", true]))).at_least(:once)
  end

  it "credits new users to the tagged campaign that first brought them, leaving out untagged first visits" do
    Google::Analytics::FirstCampaignStat.create!(date: yesterday, page_path: "/post/a", first_campaign: "new_entry", first_source: "newsletter",
      first_medium: "email", new_users: 3)
    Google::Analytics::FirstCampaignStat.create!(date: yesterday, page_path: "/post/a", first_campaign: "(organic)", first_source: "google",
      first_medium: "organic", new_users: 20)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_acquisition_breakdown_path("first-user-campaigns")

    expect(table_rows.map { |row| row.first(4) }).to eq([["1", "new_entry", "newsletter", "email"]])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(filters: include(["firstUserCampaignName", "EXACT", "(organic)", true]))).at_least(:once)
  end

  it "leaves the blog's own pages out of referrers, asking GA to do the same" do
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/post/a", referrer: "https://www.google.com/", views: 3)
    Google::Analytics::ReferrerStat.create!(date: yesterday, page_path: "/post/a", referrer: "https://harshal-ladhe.vercel.app/posts", views: 9)
    allow(Google::Analytics::LiveFigures).to receive(:call).and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")

    get google_analytics_acquisition_breakdown_path("referrers")

    expect(table_rows.map { |row| row[1] }).to eq(["https://www.google.com/"])
    expect(Google::Analytics::LiveFigures).to have_received(:call)
      .with(hash_including(filters: [["pageReferrer", "CONTAINS", "//harshal-ladhe.vercel.app", true]])).at_least(:once)
  end

  it "credits new users to the channel that first brought them, most new users first" do
    Google::Analytics::UserAcquisitionStat.create!(date: yesterday, page_path: "/post/a", first_channel_group: "Referral", first_source: "reddit.com",
      first_medium: "referral", views: 9, new_users: 2)
    Google::Analytics::UserAcquisitionStat.create!(date: yesterday, page_path: "/post/a", first_channel_group: "Organic Search", first_source: "google",
      first_medium: "organic", views: 3, new_users: 5)

    get google_analytics_acquisition_breakdown_path("user-acquisition")

    expect(Nokogiri::HTML5(response.body).css("thead th").map { |cell| cell.text.squish }).to include(start_with("First user channel"))
    expect(table_rows.map { |row| row.first(2) }).to eq([["1", "Organic Search"], ["2", "Referral"]])
  end

  it "shows each channel's total and returning users beside its new ones, asking GA for returning sessions' users apart" do
    Google::Analytics::UserAcquisitionStat.create!(date: yesterday, page_path: "/post/a", first_channel_group: "Referral", first_source: "reddit.com",
      first_medium: "referral", views: 9, new_users: 2, total_users: 4, returning_users: 2)
    Google::Analytics::UserAcquisitionStat.create!(date: yesterday - 1, page_path: "/post/a", first_channel_group: "Referral", first_source: "reddit.com",
      first_medium: "referral", views: 3, new_users: 1, total_users: 2, returning_users: 1)
    referral = ["Referral", "reddit.com", "referral"]
    allow(Google::Analytics::LiveFigures).to receive(:call) do |metrics:, filters:, **|
      if metrics == {returning_users: "activeUsers"}
        expect(filters).to eq([["newVsReturning", "EXACT", "returning"]])
        Google::Analytics::LiveFigures::Result.new(rows: {referral => {returning_users: 1}}, total: {returning_users: 1})
      else
        figures = {active_users: 4, new_users: 3, sessions: 5, engaged_sessions: 2, total_users: 4}
        Google::Analytics::LiveFigures::Result.new(rows: {referral => figures}, total: figures)
      end
    end

    get google_analytics_acquisition_breakdown_path("user-acquisition")

    headings = page_headings
    expect(headings.first(9)).to eq(["First user channel", "First user source", "First user medium", "Views", "Total users", "Active users",
      "Views per active user", "New users", "Returning users"])
    expect(table_rows.first.values_at(5, 8, 9)).to eq(["4 (100%)", "3 (100%)", "1 (100%)"])
  end

  it "adds up stored total and returning users when GA can't be asked, and says so" do
    Google::Analytics::UserAcquisitionStat.create!(date: yesterday, page_path: "/post/a", first_channel_group: "Referral", first_source: "reddit.com",
      first_medium: "referral", views: 9, new_users: 2, total_users: 4, returning_users: 2)
    Google::Analytics::UserAcquisitionStat.create!(date: yesterday - 1, page_path: "/post/a", first_channel_group: "Referral", first_source: "reddit.com",
      first_medium: "referral", views: 3, new_users: 1, total_users: 2, returning_users: 1)

    get google_analytics_acquisition_breakdown_path("user-acquisition")

    expect(table_rows.first.values_at(5, 8, 9)).to eq(["6 (100%)", "3 (100%)", "3 (100%)"])
    expect(Nokogiri::HTML5(response.body).text.squish).to include("Couldn't get users and sessions from Google Analytics")
  end

  it "queues an Analytics sync over the chosen days" do
    expect {
      post google_analytics_acquisition_sync_path("sources"), params: {google_sync_range: {from: "2026-10-06", to: "2026-10-12"}}
    }.to change(SyncRequest, :count).by(1)
    request = SyncRequest.last
    expect(request).to have_attributes(kind: "analytics", trigger: "admin", status: "queued",
      from_date: Date.new(2026, 10, 6), to_date: Date.new(2026, 10, 12))
    expect(Google::Analytics::SyncJob).to have_been_enqueued.with(7, "2026-10-12", request_id: request.id.to_s)
    expect(response).to redirect_to(google_analytics_acquisition_breakdown_path("sources"))
  end
end
