# encoding: UTF-8

require "rails_helper"

RSpec.describe "Web Vitals history", type: :request do
  include ActiveJob::TestHelper

  def page
    Nokogiri::HTML5(response.body)
  end

  it "says so before anything has synced" do
    get google_crux_web_vitals_histories_path

    expect(response).to have_http_status(:ok)
    expect(page.text).to include("No Chrome UX Report figures for this device yet.")
  end

  it "rates the latest window's metrics and charts each over time" do
    Google::Crux::Stat.create!(
      date: Date.new(2026, 10, 3),
      form_factor: "ALL",
      p75: {"lcp" => 2600.0}
    )
    Google::Crux::Stat.create!(
      date: Date.new(2026, 10, 10),
      form_factor: "ALL",
      p75: {"lcp" => 2205.0, "inp" => 520.0, "cls" => 0.03}, good: {"lcp" => 0.84}
    )
    Google::Crux::Stat.create!(
      date: Date.new(2026, 10, 10),
      form_factor: "PHONE",
      p75: {"lcp" => 4100.0}
    )

    get google_crux_web_vitals_histories_path

    rows = page.css("#latest ~ div tbody tr").map { |row| row.css("td").map { |td| td.text.squish } }
    expect(rows.first(3)).to eq(
      [
        ["Largest Contentful Paint Core Web Vital", "2,205 ms", "84.0%"],
        ["Interaction to Next Paint Core Web Vital", "520 ms", "—"],
        ["Cumulative Layout Shift Core Web Vital", "0.03", "—"]
      ]
    )
    expect(page.css("#latest ~ div tbody tr")[1].css("td")[1]["class"]).to include("text-red-700")
    expect(page.css("[id^=chart-]").size).to eq(5)

    get google_crux_web_vitals_histories_path(device: "phone")
    expect(page.css("#latest ~ div tbody tr").first.css("td")[1].text.strip).to eq("4,100 ms")
  end

  it "queues a sync" do
    expect { post sync_google_crux_web_vitals_histories_path }.to have_enqueued_job(Google::Crux::SyncJob)
  end
end
