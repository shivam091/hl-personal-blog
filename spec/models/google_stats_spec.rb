# encoding: UTF-8

require "rails_helper"

RSpec.describe "Google stats", type: :model do
  describe Google::Analytics::Traffic do
    it "works out rates from the counts, so they stay right when summed" do
      expect(Google::Analytics::Stat.new(sessions: 8, engaged_sessions: 6)).to have_attributes(engagement_rate: 0.75, bounce_rate: 0.25)
      expect(Google::Analytics::Stat.new(sessions: 0)).to have_attributes(engagement_rate: 0.0, bounce_rate: 0.0)
    end

    it "requires each breakdown's own fields" do
      stat = Google::Analytics::SourceStat.new(date: Date.current, page_path: "/")

      expect(stat).not_to be_valid
      expect(stat.errors.attribute_names).to contain_exactly(:channel_group, :source, :medium)
    end
  end

  describe Google::SearchConsole::Performance do
    it "keeps search types to the ones Search Console reports" do
      expect(Google::SearchConsole::DeviceStat.new(date: Date.current, page: "https://example.com/", device: "mobile", search_type: "maps")).not_to be_valid
    end

    it "keys rows by search type too, so the same page and day can hold each type's figures" do
      attributes = {date: Date.current, page: "https://example.com/", device: "mobile"}
      Google::SearchConsole::DeviceStat.sync([attributes.merge(search_type: "web", clicks: 1), attributes.merge(search_type: "image", clicks: 2)])

      expect(Google::SearchConsole::DeviceStat.pluck(:search_type, :clicks)).to contain_exactly(["web", 1], ["image", 2])
    end
  end

  describe Google::SearchConsole::UrlInspection do
    it "goes with its crawled page" do
      page = CrawledPage.create!(url: "https://example.com/a", last_modified_at: Time.utc(2026, 10, 1))
      Google::SearchConsole::UrlInspection.create!(crawled_page: page, verdict: "PASS")

      expect { page.destroy }.to change(Google::SearchConsole::UrlInspection, :count).by(-1)
    end

    it "spots Google indexing another URL in the page's place" do
      expect(Google::SearchConsole::UrlInspection.new(google_canonical: "https://example.com/b", user_canonical: "https://example.com/a")).to be_canonical_mismatch
      expect(Google::SearchConsole::UrlInspection.new(google_canonical: "https://example.com/a", user_canonical: "https://example.com/a")).not_to be_canonical_mismatch
      expect(Google::SearchConsole::UrlInspection.new(google_canonical: "https://example.com/a")).not_to be_canonical_mismatch
    end
  end
end
