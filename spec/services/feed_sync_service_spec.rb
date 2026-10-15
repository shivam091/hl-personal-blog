# encoding: UTF-8

require "rails_helper"

RSpec.describe FeedSyncService do
  let(:stubs) { Faraday::Adapter::Test::Stubs.new }
  let(:connection) { Faraday.new { |faraday| faraday.response :raise_error; faraday.adapter :test, stubs } }
  let(:feed_url) { "https://blog.example.com/atom.xml" }
  let(:feed) { file_fixture("atom.xml").read }

  def sync
    described_class.call(url: feed_url, connection: connection)
  end

  it "creates entries, tags, and categories from the feed" do
    stubs.get(feed_url) { [200, {}, feed] }

    result = sync

    expect(result.summary).to eq("2 created, 0 updated, 0 unchanged, 0 failed")
    expect(FeedEntry.find("https://blog.example.com/tutorial/accent-color")).to have_attributes(
      name: "Theming Native Controls with `accent-color`",
      description: "The accent-color property themes the checked and filled parts of native controls & more.",
      type: "tutorial",
      published_at: Time.utc(2026, 10, 8, 14, 2),
      last_modified_at: Time.utc(2026, 10, 8, 16, 56),
      tag_names: %w[css forms],
      category_names: %w[CSS]
    )
    expect(FeedEntry.find("https://blog.example.com/post/css/z-index")).to have_attributes(
      description: "Learn how CSS z-index really works.", category_names: %w[CSS Layout]
    )
    expect(Tag.names).to eq(%w[css forms z-index])
    expect(Category.names).to eq(%w[CSS Layout])
  end

  it "updates changed entries on a later sync and keeps entries that dropped out" do
    stubs.get(feed_url) { [200, {}, feed] }
    sync
    FeedEntry.create!(url: "https://blog.example.com/post/old", name: "Old", type: "post",
      published_at: Time.utc(2026, 1, 1), last_modified_at: Time.utc(2026, 1, 1))
    stubs.get(feed_url) { [200, {}, feed.sub("<title>Mastering CSS z-index</title>", "<title>z-index, revisited</title>")] }

    result = sync

    expect(result.summary).to eq("0 created, 1 updated, 1 unchanged, 0 failed")
    expect(FeedEntry.find("https://blog.example.com/post/css/z-index").name).to eq("z-index, revisited")
    expect(FeedEntry.count).to eq(3)
  end

  it "reports invalid entries and carries on" do
    stubs.get(feed_url) { [200, {}, feed.sub('term="post"', 'term="page"')] }

    result = sync

    expect(result.created).to eq(1)
    expect(result.errors).to eq(["https://blog.example.com/post/css/z-index: Type must be one of post, tutorial, snippet, series"])
  end

  it "reports an unreachable or malformed feed instead of raising" do
    stubs.get(feed_url) { [503, {}, "down"] }
    expect(sync.errors.first).to start_with("Couldn't read #{feed_url}")

    stubs.get("https://blog.example.com/broken.xml") { [200, {}, "<feed><entry>"] }
    broken = described_class.call(url: "https://blog.example.com/broken.xml", connection: connection)
    expect(broken.errors.first).to start_with("Couldn't read")
    expect(FeedEntry.count).to eq(0)
  end

  describe "feed URL" do
    before do
      allow(ENV).to receive(:[]).and_call_original
    end

    def stub_sources(env:, blog_url:)
      allow(ENV).to receive(:[]).with("ATOM_FEED_URL") { env }
      allow(Rails.application.credentials).to receive(:blog) { {url: blog_url} }
    end

    it "prefers ATOM_FEED_URL over the blog's own feed" do
      stub_sources(env: feed_url, blog_url: "https://other.example.com")
      stubs.get(feed_url) { [200, {}, feed] }

      expect(described_class.call(connection: connection).created).to eq(2)
    end

    it "falls back to the feed at credentials blog.url" do
      stub_sources(env: "", blog_url: feed_url.delete_suffix("/atom.xml"))
      stubs.get(feed_url) { [200, {}, feed] }

      expect(described_class.call(connection: connection).created).to eq(2)
    end

    it "reports when neither is set" do
      stub_sources(env: nil, blog_url: nil)

      expect(described_class.call(connection: connection).errors).to eq(["No feed URL configured (ATOM_FEED_URL or credentials blog.url)"])
    end
  end
end
