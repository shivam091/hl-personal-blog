# encoding: UTF-8

require "rails_helper"

RSpec.describe PageView, type: :model do
  let(:source_doc) do
    {
      "_id" => "/post/git/advanced-git-techniques-and-workflows",
      "slug" => "/post/git/advanced-git-techniques-and-workflows",
      "url" => "https://harshal-ladhe.vercel.app/post/git/advanced-git-techniques-and-workflows",
      "countries" => {"IN" => 2},
      "devices" => {"desktop" => 2},
      "referrers" => {"internal" => 2},
      "viewsByDay" => {"2026-08-23" => 2},
      "countriesByDay" => {"2026-08-23" => {"IN" => 2}},
      "uniqueVisitorCount" => 1,
      "visitorCount" => 2,
      "botCount" => 3,
      "createdAt" => Time.zone.parse("2026-08-23T06:59:21.224Z"),
      "updatedAt" => Time.zone.parse("2026-08-23T07:00:20.372Z")
    }
  end

  it "reads the frontend's camelCase fields through snake_case aliases" do
    PageView.collection.insert_one(source_doc)
    view = PageView.find(source_doc["_id"])

    expect(view.slug).to eq("/post/git/advanced-git-techniques-and-workflows")
    expect(view.url).to eq("https://harshal-ladhe.vercel.app/post/git/advanced-git-techniques-and-workflows")
    expect(view.legacy_countries).to eq("IN" => 2)
    expect(view.devices).to eq("desktop" => 2)
    expect(view.referrers).to eq("internal" => 2)
    expect(view.legacy_views_by_day).to eq("2026-08-23" => 2)
    expect(view.countries_by_day).to eq("2026-08-23" => {"IN" => 2})
    expect(view.unique_visitor_count).to eq(1)
    expect(view.visitor_count).to eq(2)
    expect(view.bot_count).to eq(3)
    expect(view.updated_at).to eq(source_doc["updatedAt"])
  end

  it "totals countries from legacy counts plus the dated breakdown" do
    PageView.collection.insert_one(source_doc.merge(
      "countries" => {"IN" => 2, "US" => 1},
      "countriesByDay" => {"2026-10-10" => {"IN" => 3}, "2026-10-11" => {"GB" => 1, "IN" => 1}}
    ))

    expect(PageView.first.countries).to eq("IN" => 6, "US" => 1, "GB" => 1)
  end

  it "totals views by day from legacy counts plus the dated breakdown" do
    PageView.collection.insert_one(source_doc.merge(
      "viewsByDay" => {"2026-10-09" => 4, "2026-10-10" => 2},
      "countriesByDay" => {"2026-10-10" => {"IN" => 3}, "2026-10-11" => {"GB" => 1, "IN" => 1}}
    ))

    expect(PageView.first.views_by_day).to eq("2026-10-09" => 4, "2026-10-10" => 5, "2026-10-11" => 2)
  end

  it "totals devices and referrers from legacy counts plus the dated breakdowns" do
    PageView.collection.insert_one(source_doc.merge(
      "devicesByDay" => {"2026-10-10" => {"desktop" => 1, "mobile" => 4}},
      "referrersByDay" => {"2026-10-10" => {"google_com" => 3}, "2026-10-11" => {"internal" => 1}}
    ))
    view = PageView.first

    expect(view.legacy_devices).to eq("desktop" => 2)
    expect(view.devices).to eq("desktop" => 3, "mobile" => 4)
    expect(view.referrers).to eq("internal" => 3, "google_com" => 3)
    expect(view.devices_by_day).to eq("2026-10-10" => {"desktop" => 1, "mobile" => 4})
  end

  it "counts devices and referrers within a period" do
    PageView.collection.insert_one(source_doc.merge(
      "devicesByDay" => {"2026-10-10" => {"mobile" => 4}, "2026-09-01" => {"desktop" => 1}, "bad-day" => {"tablet" => 1}},
      "referrersByDay" => {"2026-10-10" => {"google_com" => 3}, "2026-10-11" => {"internal" => 1}}
    ))
    view = PageView.first
    period = Period.new({from: "2026-10-10", to: "2026-10-10"})

    expect(view.devices_within(period)).to eq("mobile" => 4)
    expect(view.referrers_within(period)).to eq("google_com" => 3)
  end

  it "is read-only" do
    PageView.collection.insert_one(source_doc)
    view = PageView.find(source_doc["_id"])

    view.visitor_count = 9
    expect { view.save! }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect { PageView.new.save! }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect { view.destroy }.to raise_error(Mongoid::Errors::ReadonlyDocument)
    expect(PageView.collection.find(_id: source_doc["_id"]).first["visitorCount"]).to eq(source_doc["visitorCount"])
  end

  it "sorts by aliased fields" do
    PageView.collection.insert_many([
      source_doc.merge("_id" => "/a", "slug" => "/a", "visitorCount" => 1),
      source_doc.merge("_id" => "/b", "slug" => "/b", "visitorCount" => 5)
    ])

    expect(PageView.order(visitor_count: :desc).pluck(:slug)).to eq(["/b", "/a"])
  end

  it "defaults breakdown hashes to empty when absent" do
    PageView.collection.insert_one(source_doc.except("countries", "devices", "referrers", "viewsByDay", "countriesByDay"))
    view = PageView.first

    expect(view.legacy_countries).to eq({})
    expect(view.countries).to eq({})
    expect(view.devices).to eq({})
    expect(view.referrers).to eq({})
    expect(view.legacy_views_by_day).to eq({})
    expect(view.views_by_day).to eq({})
    expect(view.countries_by_day).to eq({})
  end

  it "ranks pages by their share of hits from bots, leaving out pages with too few" do
    PageView.collection.insert_many([
      {"_id" => "/a", "slug" => "/a", "botCount" => 10, "visitorCount" => 30},
      {"_id" => "/b", "slug" => "/b", "botCount" => 15, "visitorCount" => 5},
      {"_id" => "/c", "slug" => "/c", "botCount" => 5, "visitorCount" => 5}
    ])

    expect(PageView.bot_shares).to eq([["/b", 15, 5, 0.75], ["/a", 10, 30, 0.25]])
  end

  it "adds up each campaign's visits in a period across every page" do
    PageView.collection.insert_many([
      {"_id" => "/a", "slug" => "/a", "campaignsByDay" => {"2026-10-01" => {"newsletter|email|new_entry" => 3}, "2026-09-01" => {"newsletter|email|new_entry" => 9}}},
      {"_id" => "/b", "slug" => "/b", "campaignsByDay" => {"2026-10-02" => {"newsletter|email|new_entry" => 2, "news_ycombinator_com|(none)|(none)" => 1}}}
    ])

    campaigns = described_class.campaigns_within(Period.new({from: "2026-10-01", to: "2026-10-31"}))

    expect(campaigns).to eq("newsletter|email|new_entry" => 5, "news_ycombinator_com|(none)|(none)" => 1)
  end

  # safeKey can't be undone, so underscores stay as written, and a key cut
  # at 64 characters loses its later parts.
  it "splits a campaign key back into its source, medium and name" do
    expect(described_class.campaign("newsletter|email|new_entry|title|tutorial|tutorials-grid").to_a)
      .to eq(%w[newsletter email new_entry title tutorial tutorials-grid])
    expect(described_class.campaign("#{"x" * 60}|social").to_a).to eq(["x" * 60, "social", "(none)", "(none)", "(none)", "(none)"])
  end

  # The frontend owns this collection's indexes; db:mongoid:create_indexes
  # runs on every deploy and would add ours to its live collection.
  it "declares no indexes" do
    expect(described_class.index_specifications).to be_empty
  end
end
