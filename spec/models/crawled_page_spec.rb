# encoding: UTF-8

require "rails_helper"

RSpec.describe CrawledPage, type: :model do
  let(:csv) { file_fixture("crawled-pages.csv").read }

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
      allow(page).to receive(:valid?) { true } # as if a concurrent save won the race

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

  describe ".import_csv" do
    it "creates a page per row" do
      result = CrawledPage.import_csv(csv)

      expect(result.summary).to eq("3 created, 0 updated, 0 unchanged, 0 failed")
      home = CrawledPage.find_by(url: "https://harshal-ladhe.vercel.app")
      expect(home.last_modified_at).to eq(Time.utc(2026, 7, 5, 12, 7, 1))
      expect(home.indexed).to be_truthy
      expect(CrawledPage.find_by(url: "https://harshal-ladhe.vercel.app/tutorials").indexed).to be_falsy
    end

    it "updates last modified and status of existing URLs, and leaves unchanged ones alone" do
      CrawledPage.import_csv(csv)
      changed = csv.sub("2026-06-29T10:59:17.000Z,", "2026-10-01T09:00:00.000Z,Yes")

      expect {
        expect(CrawledPage.import_csv(changed).summary).to eq("0 created, 1 updated, 2 unchanged, 0 failed")
      }.not_to change(CrawledPage, :count)

      tutorials = CrawledPage.find_by(url: "https://harshal-ladhe.vercel.app/tutorials")
      expect(tutorials.last_modified_at).to eq(Time.utc(2026, 10, 1, 9))
      expect(tutorials.indexed).to be_truthy
    end

    it "skips and reports invalid rows" do
      bad = csv + "11,not-a-url,2026-06-29T10:59:17.000Z,\n12,https://example.com/x,yesterday,Yes\n"

      result = CrawledPage.import_csv(bad)

      expect(result.summary).to eq("3 created, 0 updated, 0 unchanged, 2 failed")
      expect(result.errors[0]).to eq("Line 5: URL must be an http(s) URL")
      expect(result.errors[1]).to start_with("Line 6: invalid Last modified \"yesterday\"")
    end

    it "handles a UTF-8 byte order mark before the header" do
      expect(CrawledPage.import_csv("﻿" + csv).summary).to eq("3 created, 0 updated, 0 unchanged, 0 failed")
    end

    it "reports a file without a URL column" do
      result = CrawledPage.import_csv("Link,Status\nhttps://example.com,Yes\n")

      expect(result.errors).to eq(["Line 1: missing a URL column (expected #,URL,Last modified,Status)"])
      expect(CrawledPage.count).to eq(0)
    end
  end

  describe ".to_csv" do
    it "exports in the layout .import_csv reads" do
      CrawledPage.import_csv(csv)

      expect(CrawledPage.to_csv).to eq(<<~CSV)
        #,URL,Last modified,Status
        1,https://harshal-ladhe.vercel.app,2026-07-05T12:07:01.000Z,Yes
        2,https://harshal-ladhe.vercel.app/about,2026-08-23T14:42:36.000Z,Yes
        3,https://harshal-ladhe.vercel.app/tutorials,2026-06-29T10:59:17.000Z,
      CSV
    end
  end
end
