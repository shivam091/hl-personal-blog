# encoding: UTF-8

require "rails_helper"

RSpec.describe SitemapSyncService do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) { Faraday.new { |faraday| faraday.response :raise_error; faraday.adapter :test, stubs } }
  let(:sitemap_url) { "https://blog.example.com/sitemap.xml" }

  def urlset(*entries)
    urls = entries.map do |loc, lastmod|
      "<url><loc>#{loc}</loc>#{"<lastmod>#{lastmod}</lastmod>" if lastmod}<changefreq>weekly</changefreq></url>"
    end
    %(<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">#{urls.join}</urlset>)
  end

  def sync
    described_class.call(url: sitemap_url, connection: connection)
  end

  it "creates new pages and updates last modified on known ones, leaving indexed status alone" do
    known = CrawledPage.create!(url: "https://blog.example.com/about", last_modified_at: Time.utc(2026, 1, 1), indexed: true)
    same = CrawledPage.create!(url: "https://blog.example.com/contact", last_modified_at: Time.utc(2026, 6, 19, 17, 11, 49))
    stubs.get(sitemap_url) do
      [200, {}, urlset(
        ["https://blog.example.com/about", "2026-08-23T14:42:36.000Z"],
        ["https://blog.example.com/contact", "2026-06-19T17:11:49.000Z"],
        ["https://blog.example.com/new-post", "2026-10-08T05:14:16.000Z"]
      )]
    end

    result = sync

    expect(result.summary).to eq("1 created, 1 updated, 1 unchanged, 0 failed")
    expect(known.reload).to have_attributes(last_modified_at: Time.utc(2026, 8, 23, 14, 42, 36), indexed: true)
    expect(same.reload.last_modified_at).to eq(Time.utc(2026, 6, 19, 17, 11, 49))
    expect(CrawledPage.find_by(url: "https://blog.example.com/new-post")).to have_attributes(
      last_modified_at: Time.utc(2026, 10, 8, 5, 14, 16), indexed: false
    )
  end

  it "keeps pages that dropped out of the sitemap" do
    CrawledPage.create!(url: "https://blog.example.com/old-post", last_modified_at: Time.utc(2026, 7, 5))
    stubs.get(sitemap_url) { [200, {}, urlset(["https://blog.example.com/new", "2026-07-05"])] }

    sync

    expect(CrawledPage.pluck(:url)).to contain_exactly("https://blog.example.com/old-post", "https://blog.example.com/new")
  end

  it "accepts day-only lastmod dates" do
    stubs.get(sitemap_url) { [200, {}, urlset(["https://blog.example.com/a", "2026-07-05"])] }

    sync

    expect(CrawledPage.find_by(url: "https://blog.example.com/a").last_modified_at).to eq(Time.utc(2026, 7, 5))
  end

  it "follows a sitemap index" do
    stubs.get(sitemap_url) do
      [200, {}, %(<sitemapindex xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><sitemap><loc>https://blog.example.com/posts.xml</loc></sitemap></sitemapindex>)]
    end
    stubs.get("https://blog.example.com/posts.xml") { [200, {}, urlset(["https://blog.example.com/post/1", "2026-07-05"])] }

    expect(sync.created).to eq(1)
  end

  it "reports invalid entries and carries on" do
    stubs.get(sitemap_url) { [200, {}, urlset(["ftp://blog.example.com/file", "2026-07-05"], ["https://blog.example.com/ok", "2026-07-05"])] }

    result = sync

    expect(result.created).to eq(1)
    expect(result.errors).to eq(["ftp://blog.example.com/file: URL must be an http(s) URL"])
  end

  it "reports an unreachable or malformed sitemap instead of raising" do
    stubs.get(sitemap_url) { [503, {}, "down"] }
    expect(sync.errors.first).to start_with("Couldn't read #{sitemap_url}")

    stubs.get("https://blog.example.com/broken.xml") { [200, {}, "<urlset><url>"] }
    broken = described_class.call(url: "https://blog.example.com/broken.xml", connection: connection)
    expect(broken.errors.first).to start_with("Couldn't read")
    expect(CrawledPage.count).to eq(0)
  end
end
