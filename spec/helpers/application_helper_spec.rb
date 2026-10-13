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
end
