# encoding: UTF-8

require "rails_helper"

RSpec.describe CrawledPage, type: :model do
  it "requires a unique http(s) URL" do
    expect(CrawledPage.new).not_to be_valid

    page = CrawledPage.new(url: "not a url")
    expect(page).not_to be_valid
    expect(page.errors[:url]).to include("must be an http(s) URL")

    CrawledPage.create!(url: "https://example.com/a", last_modified_at: Time.utc(2026, 7, 5))
    expect(CrawledPage.new(url: " https://example.com/a ", last_modified_at: Time.utc(2026, 7, 5))).not_to be_valid
  end

  describe "validations" do
    def errors_for(**attributes)
      page = CrawledPage.new(url: "https://example.com/a", last_modified_at: Time.utc(2026, 7, 5), **attributes)
      page.validate
      page.errors.to_hash(true)
    end

    it "accepts a valid page" do
      expect(errors_for(last_modified_at: "2026-07-05T12:07:01Z", indexed: "1")).to be_empty
    end

    it "rejects URLs that aren't http(s) with a host" do
      ["ftp://example.com/a", "https://", "example.com/a", "https://exa mple.com", "javascript:alert(1)"].each do |url|
        expect(errors_for(url: url)).to eq({url: ["URL must be an http(s) URL"]}), url
      end
    end

    it "rejects overlong URLs" do
      url = "https://example.com/#{"a" * CrawledPage::MAX_URL_LENGTH}"
      expect(errors_for(url: url)[:url]).to include("URL is too long (maximum is 2048 characters)")
    end

    it "requires a last modified, and rejects an unparseable one instead of calling it blank" do
      expect(errors_for(last_modified_at: "garbage")).to eq({last_modified_at: ["Last modified is not a valid date and time"]})
      expect(errors_for(last_modified_at: "")).to eq({last_modified_at: ["Last modified can't be blank"]})
    end

    it "rejects a last modified in the future" do
      expect(errors_for(last_modified_at: 1.day.from_now)).to eq({last_modified_at: ["Last modified can't be in the future"]})
    end

    it "rejects an indexed value that isn't a boolean" do
      expect(errors_for(indexed: "maybe")).to eq({indexed: ["Indexed must be yes or no"]})
    end

    it "reports a duplicate URL caught only by the unique index as a validation error" do
      CrawledPage.create_indexes
      CrawledPage.create!(url: "https://example.com/a", last_modified_at: Time.utc(2026, 7, 5))
      page = CrawledPage.new(url: "https://example.com/a", last_modified_at: Time.utc(2026, 7, 5))
      # So only the unique index can refuse it, as if a concurrent save won the race.
      allow(page).to receive(:valid?) { true }

      expect(page.save).to be_falsy
      expect(page.errors[:url]).to eq(["has already been taken"])
    ensure
      CrawledPage.remove_indexes
    end
  end

  it "defaults to not indexed and uses its URL as to_s" do
    page = CrawledPage.new(url: "https://example.com/a")

    expect(page.indexed).to be_falsy
    expect(page.to_s).to eq("https://example.com/a")
  end
end
