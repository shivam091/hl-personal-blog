# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::SearchConsole::SitemapSubmitService do
  let(:site) { "sc-domain:blog.example.com" }
  let(:sitemap) { "https://blog.example.com/sitemap.xml" }
  let(:url) { "https://searchconsole.googleapis.com/webmasters/v3/sites/sc-domain%3Ablog.example.com/sitemaps/https%3A%2F%2Fblog.example.com%2Fsitemap.xml" }
  let(:refresh) { class_double(Google::SearchConsole::SitemapSyncService, call: SyncResult.empty) }

  def submit(**options)
    described_class.call(site: site, sitemap: sitemap, client: google_client, refresh: refresh, **options)
  end

  it "submits the sitemap, then refreshes how Search Console lists it" do
    submitted = []
    google_stubs.put(url) do |env|
      submitted << env.url.to_s
      [204, {}, ""]
    end

    expect(submit.summary).to eq("0 created, 1 updated, 0 unchanged, 0 failed")
    expect(submitted.size).to eq(1)
    expect(refresh).to have_received(:call)
  end

  it "reports Google's refusal, such as a read-only service account" do
    google_stubs.put(url) { [403, {}, {error: {message: "User does not have sufficient permission for site"}}.to_json] }

    expect(submit.errors).to eq(["Sitemap submission: User does not have sufficient permission for site"])
    expect(refresh).not_to have_received(:call)
  end

  it "says why without a sitemap" do
    expect(submit(sitemap: nil).errors).to eq(["No sitemap configured (credentials blog.url)"])
  end
end
