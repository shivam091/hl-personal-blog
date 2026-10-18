# encoding: UTF-8

require "rails_helper"

RSpec.describe "reCAPTCHA logins", type: :request do
  let!(:accepted) do
    Google::Recaptcha::Assessment.create!(action: "login", expected_action: "login", score: 0.9, valid_token: true, accepted: true,
      remote_ip: "203.0.113.5", user_agent: "Firefox", password_outcome: "CORRECT_PASSWORD", created_at: Time.utc(2026, 10, 11))
  end
  let!(:rejected) do
    Google::Recaptcha::Assessment.create!(action: "login", expected_action: "login", score: 0.1, valid_token: true, accepted: false,
      reasons: ["AUTOMATION"], remote_ip: "198.51.100.7", user_agent: "curl/8.0", created_at: Time.utc(2026, 10, 12))
  end

  it "lists checks newest first, filterable by outcome and searchable by reason" do
    get google_recaptcha_assessments_path

    rows = Nokogiri::HTML5(response.body).css("tbody tr")
    expect(rows.map { |row| row.css("td").last.text.squish }).to eq(["198.51.100.7 curl/8.0", "203.0.113.5 Firefox"])
    expect(rows.first.text).to include("Rejected", "Automation")

    get google_recaptcha_assessments_path(accepted: "yes")
    expect(response.body).to include("203.0.113.5")
    expect(response.body).not_to include("198.51.100.7")

    get google_recaptcha_assessments_path(reason: "automation")
    expect(response.body).to include("198.51.100.7")
    expect(response.body).not_to include("203.0.113.5")
  end

  it "lays the list out as saved in its settings" do
    ListSetting.create!(list: "recaptcha_assessments", order: %w[score created_at action outcome password client], hidden: %w[action client],
      sort: "score", direction: "asc", row_numbers: false)

    get google_recaptcha_assessments_path

    page = Nokogiri::HTML5(response.body)
    expect(page.css("thead th").map { |th| th.text.squish }).to eq(%w[Score Time Outcome Password])
    expect(page.css("tbody tr").map { |row| row.css("td").size }).to eq([4, 4])
    expect(page.css("tbody tr").first.text).to include("Rejected")
    expect(page.at_css("a[href='#{edit_list_setting_path("recaptcha_assessments")}']")).to be_present
  end

  it "adds up the listed checks, by day, by score and password, and by repeat address" do
    Google::Recaptcha::Assessment.create!(action: "login", score: 0.3, accepted: false, remote_ip: "198.51.100.7",
      password_outcome: "INCORRECT_PASSWORD", created_at: Time.utc(2026, 10, 12, 1))

    get google_recaptcha_assessments_path(time_from: "2026-10-10", time_to: "2026-10-12")

    page = Nokogiri::HTML5(response.body)
    expect(page.css("#login-figures dd.text-lg").map(&:text)).to eq(%w[3 2 1 2])
    days = page.css("section[aria-labelledby=login-attempts] [data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
    expect(days.map { |day| day["rows"].map { |row| row["value"] } }).to eq([%w[0 0], %w[1 0], %w[0 2]])
    scores = page.css("section[aria-labelledby=login-scores] [data-tip]").to_h do |bar|
      tip = JSON.parse(bar["data-tip"])
      [tip["title"], tip["rows"].map { |row| row["value"] }]
    end
    expect(scores.values_at("0.1", "0.3", "0.9")).to eq([%w[0 0 1], %w[0 1 0], %w[1 0 0]])
    addresses = page.css("section[aria-labelledby=repeat-addresses] li")
    expect(addresses.size).to eq(1)
    expect(addresses.first.text.squish).to include("198.51.100.7 2 attempts 2 rejected 1 wrong password Last")
    expect(addresses.first.at_css("a")["href"]).to eq(google_recaptcha_assessments_path(ip: "198.51.100.7"))

    get google_recaptcha_assessments_path(accepted: "yes")
    expect(Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=repeat-addresses]").text).to include("No address tried more than once.")
  end

  it "shows one check in full" do
    get google_recaptcha_assessment_path(rejected)

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("h1").text).to eq("login check from 198.51.100.7")
    expect(page.at_css("#assessment").parent.text).to include("AUTOMATION", "Rejected")
  end

  it "exports the filtered checks" do
    get google_recaptcha_assessments_path(format: :csv, password: "CORRECT_PASSWORD")

    csv = CSV.parse(response.body, headers: true)
    expect(csv.map { |row| [row["IP"], row["Accepted"], row["Password outcome"]] }).to eq([["203.0.113.5", "Yes", "CORRECT_PASSWORD"]])
  end
end
