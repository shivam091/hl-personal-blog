# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::PageSpeed::SyncService do
  let(:url) { "https://www.googleapis.com/pagespeedonline/v5/runPagespeed" }
  let(:home) { "https://blog.example.com/" }
  let(:requests) { [] }

  def psi_response(performance: 0.92, page_metrics: true)
    experience = ->(lcp, inp, cls) {
      {
        "metrics" => {
          "LARGEST_CONTENTFUL_PAINT_MS" => {"percentile" => lcp},
          "INTERACTION_TO_NEXT_PAINT" => {"percentile" => inp},
          "CUMULATIVE_LAYOUT_SHIFT_SCORE" => {"percentile" => cls}
        },
        "overall_category" => "FAST"
      }
    }
    {
      "lighthouseResult" => {
        "categories" => {
          "performance" => {"score" => performance},
          "accessibility" => {"score" => 1},
          "best-practices" => {"score" => 0.96},
          "seo" => {"score" => 1}
        },
        "audits" => {
          "largest-contentful-paint" => {"numericValue" => 1834.2},
          "cumulative-layout-shift" => {"numericValue" => 0.01},
          "total-blocking-time" => {"numericValue" => 40},
          "first-contentful-paint" => {"numericValue" => 900},
          "speed-index" => {"numericValue" => 1200}
        }
      },
      "loadingExperience" => page_metrics ? experience.(2100, 150, 5) : {"id" => "x"},
      "originLoadingExperience" => experience.(2600, 210, 12)
    }
  end

  def sync(**options)
    described_class.call(client: google_key_client, home: home, **options)
  end

  before do
    FeedEntry.create!(
      url: "https://blog.example.com/post/a",
      name: "A",
      type: "post",
      published_at: 1.day.ago,
      last_modified_at: 1.day.ago
    )
  end

  it "tests each page on mobile and desktop, keeping Lighthouse's scores and real users' Core Web Vitals" do
    google_stubs.get(url) do |env|
      requests << env.params
      [200, {}, psi_response.to_json]
    end

    expect(sync.summary).to eq("4 created, 0 updated, 0 unchanged, 0 failed")
    expect(requests.map { |params| [params["url"], params["strategy"]] }).to contain_exactly(
      [home, "mobile"],
      [home, "desktop"],
      ["https://blog.example.com/post/a", "mobile"],
      ["https://blog.example.com/post/a", "desktop"]
    )
    expect(requests.first["key"]).to eq("test-key")
    expect(Google::PageSpeed::Result.find_by(url: "https://blog.example.com/post/a", strategy: "mobile")).to have_attributes(
      page_path: "/post/a",
      performance: 0.92,
      accessibility: 1.0,
      best_practices: 0.96,
      seo: 1.0,
      lab_lcp_ms: 1834.2,
      lab_tbt_ms: 40.0,
      field_lcp_ms: 2100.0,
      field_inp_ms: 150.0,
      field_cls: 0.05,
      field_category: "FAST",
      field_source: "page",
      error: nil
    )
  end

  it "asks for every Lighthouse category" do
    google_stubs.get(url) do |env|
      requests << env.url.query
      [200, {}, psi_response.to_json]
    end

    sync(limit: 1)
    expect(requests.first.scan(/category=([A-Z_]+)/).flatten).to eq(%w[PERFORMANCE ACCESSIBILITY BEST_PRACTICES SEO])
  end

  it "takes the whole site's field figures when the page has too few Chrome users, and says so" do
    google_stubs.get(url) { [200, {}, psi_response(page_metrics: false).to_json] }

    sync(limit: 1)
    expect(Google::PageSpeed::Result.first).to have_attributes(
      field_lcp_ms: 2600.0,
      field_inp_ms: 210.0,
      field_cls: 0.12,
      field_source: "origin"
    )
  end

  it "tests the least recently tested pages first" do
    Google::PageSpeed::Result.create!(url: home, strategy: "mobile", fetched_at: 1.hour.ago)
    google_stubs.get(url) do |env|
      requests << env.params["url"]
      [200, {}, psi_response.to_json]
    end

    sync(limit: 1)
    expect(requests.uniq).to eq(["https://blog.example.com/post/a"])
  end

  it "dates a failed test, keeping the last figures, so the page waits its turn" do
    Google::PageSpeed::Result.create!(url: home, strategy: "mobile", performance: 0.8, fetched_at: 2.days.ago)
    google_stubs.get(url) { [500, {}, {error: {message: "Lighthouse returned error: FAILED_DOCUMENT_REQUEST"}}.to_json] }

    result = sync
    expect(result.errors.first).to eq("PageSpeed of https://blog.example.com/post/a: Lighthouse returned error: FAILED_DOCUMENT_REQUEST")
    expect(Google::PageSpeed::Result.find_by(url: home, strategy: "mobile")).to have_attributes(
      performance: 0.8,
      error: "Lighthouse returned error: FAILED_DOCUMENT_REQUEST"
    )
    expect(Google::PageSpeed::Result.find_by(url: home, strategy: "mobile").fetched_at).to be > 1.minute.ago
  end

  it "says why without an API key" do
    expect(described_class.call(client: google_key_client(api_key: nil)).errors).to eq(
      ["Google API key not configured (credentials google.api_key)"]
    )
  end
end
