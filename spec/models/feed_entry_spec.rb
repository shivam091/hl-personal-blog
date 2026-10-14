# encoding: UTF-8

require "rails_helper"

RSpec.describe FeedEntry, type: :model do
  def source(url = "https://example.com/a", **attributes)
    FeedEntry::Source.new(label: url, url: url, name: "A", description: "About A", type: "post",
      published_at: Time.utc(2026, 7, 5), last_modified_at: Time.utc(2026, 7, 6), tags: %w[css], categories: %w[CSS],
      **attributes)
  end

  describe "validations" do
    def errors_for(**attributes)
      entry = FeedEntry.new(url: "https://example.com/a", name: "A", type: "post",
        published_at: Time.utc(2026, 7, 5), last_modified_at: Time.utc(2026, 7, 5), **attributes)
      entry.validate
      entry.errors.to_hash(true)
    end

    it "accepts a valid entry" do
      expect(errors_for).to be_empty
    end

    it "keys entries on their URL" do
      entry = FeedEntry.create!(url: " https://example.com/a ", name: "A", type: "post",
        published_at: Time.utc(2026, 7, 5), last_modified_at: Time.utc(2026, 7, 5))

      expect(entry.id).to eq("https://example.com/a")
      expect(FeedEntry.find("https://example.com/a")).to eq(entry)
    end

    it "rejects URLs that aren't http(s) with a host" do
      ["ftp://example.com/a", "https://", "example.com/a", "javascript:alert(1)"].each do |url|
        expect(errors_for(url: url)).to eq({url: ["URL must be an http(s) URL"]}), url
      end
    end

    it "requires a title and both dates" do
      expect(errors_for(name: " ", published_at: nil, last_modified_at: nil)).to eq({
        name: ["Title can't be blank"],
        published_at: ["Published can't be blank"],
        last_modified_at: ["Updated can't be blank"]
      })
    end

    it "only accepts the blog's content types" do
      expect(errors_for(type: "page")).to eq({type: ["Type must be one of post, tutorial, snippet, series"]})
    end
  end

  describe ".import" do
    it "creates entries with their tags and categories, creating the taxonomy as needed" do
      Tag.create!(name: "css")

      result = FeedEntry.import([source(tags: %w[css forms], categories: %w[CSS])])

      expect(result.summary).to eq("1 created, 0 updated, 0 unchanged, 0 failed")
      expect(Tag.names).to eq(%w[css forms])
      expect(Category.names).to eq(%w[CSS])
      expect(FeedEntry.find("https://example.com/a")).to have_attributes(tag_names: %w[css forms], category_names: %w[CSS])
    end

    it "updates entries that changed and leaves the rest alone" do
      FeedEntry.import([source, source("https://example.com/b")])

      result = FeedEntry.import([source(name: "A, renamed", tags: %w[css html]), source("https://example.com/b")])

      expect(result.summary).to eq("0 created, 1 updated, 1 unchanged, 0 failed")
      expect(FeedEntry.find("https://example.com/a")).to have_attributes(name: "A, renamed", tag_names: %w[css html])
    end

    it "keeps tags in the source's order" do
      FeedEntry.import([source(tags: %w[z-index css layout])])

      expect(FeedEntry.find("https://example.com/a").tag_names).to eq(%w[z-index css layout])
    end

    it "reports invalid entries and carries on" do
      result = FeedEntry.import([source("ftp://example.com/x"), source(type: "page"), source("https://example.com/ok")])

      expect(result.created).to eq(1)
      expect(result.errors).to eq([
        "ftp://example.com/x: URL must be an http(s) URL",
        "https://example.com/a: Type must be one of post, tutorial, snippet, series"
      ])
    end

    it "treats a URL listed twice as an update the second time" do
      result = FeedEntry.import([source, source(name: "A again")])

      expect(result.summary).to eq("1 created, 1 updated, 0 unchanged, 0 failed")
      expect(FeedEntry.find("https://example.com/a").name).to eq("A again")
    end
  end

  describe ".to_csv" do
    it "writes tags and categories comma-separated in one cell" do
      FeedEntry.import([source(tags: %w[css forms], categories: %w[CSS])])

      expect(FeedEntry.to_csv).to eq(<<~CSV)
        #,URL,Title,Description,Type,Published,Updated,Tags,Categories
        1,https://example.com/a,A,About A,post,2026-07-05T00:00:00.000Z,2026-07-06T00:00:00.000Z,"css, forms",CSS
      CSV
    end
  end
end
