# encoding: UTF-8

require "rails_helper"

RSpec.describe ApplicationHelper, type: :helper do
  before { allow(Blog).to receive(:url) { "https://blog.example.com" } }

  it "finds the live page for a blog path on the blog's host, and keeps a full URL as it is" do
    expect(helper.blog_live_url("/post/a")).to eq("https://blog.example.com/post/a")
    expect(helper.blog_live_url("https://blog.example.com/post/b")).to eq("https://blog.example.com/post/b")
    expect(helper.blog_live_url("javascript:alert(1)")).to be_nil
    expect(helper.blog_live_url("post/a")).to be_nil
  end

  it "has no live page for a path while the blog's host isn't known" do
    allow(Blog).to receive(:url) { nil }

    expect(helper.blog_live_url("/post/a")).to be_nil
  end

  it "links a blog page here, with its live page in a new tab beside it" do
    html = Nokogiri::HTML5.fragment(helper.blog_page_link("/post/a", "/page-views/%2Fpost%2Fa"))
    own, live = html.css("a")

    expect(own).to have_attributes(text: "/post/a")
    expect(own["href"]).to eq("/page-views/%2Fpost%2Fa")
    expect(own["class"]).not_to include("font-mono")
    expect(%w[href target rel aria-label].to_h { |name| [name, live[name]] }).to eq(
      "href" => "https://blog.example.com/post/a", "target" => "_blank", "rel" => "noopener", "aria-label" => "Open /post/a on the blog"
    )
  end

  it "shows a page with nothing of its own here as text, still with its live page" do
    html = Nokogiri::HTML5.fragment(helper.blog_page_link("https://blog.example.com/post/a", nil))

    expect(html.css("a").map { |link| link["href"] }).to eq(["https://blog.example.com/post/a"])
    expect(html.at_css("span span").text).to eq("https://blog.example.com/post/a")
  end

  describe "#period_dates" do
    def dates(from, to, **options)
      Nokogiri::HTML5.fragment(helper.period_dates(Period.new({from: from, to: to}), **options))
    end

    def seen(fragment)
      fragment.dup.tap { |copy| copy.css(".sr-only").each(&:remove) }.text
    end

    it "writes both ends in full, as time tags read as a range" do
      range = dates("2026-10-14", "2026-11-10")

      expect(seen(range)).to eq("14 Oct, 2026 – 10 Nov, 2026")
      expect(range.css("time").map { |time| time["datetime"] }).to eq(%w[2026-10-14 2026-11-10])
      expect(range.at_css("[aria-hidden=true]").text).to eq(" – ")
      expect(range.at_css(".sr-only").text).to eq(" to ")
    end

    it "writes the year once when compact and both ends share it" do
      expect(seen(dates("2026-10-14", "2026-11-10", compact: true))).to eq("14 Oct – 10 Nov 2026")
    end

    it "keeps both years when a compact range crosses one" do
      expect(seen(dates("2025-12-20", "2026-01-16", compact: true))).to eq("20 Dec 2025 – 16 Jan 2026")
    end

    it "writes a single day once" do
      expect(dates("2026-11-10", "2026-11-10").text).to eq("10 Nov, 2026")
      expect(dates("2026-11-10", "2026-11-10", compact: true).text).to eq("10 Nov 2026")
    end
  end
end
