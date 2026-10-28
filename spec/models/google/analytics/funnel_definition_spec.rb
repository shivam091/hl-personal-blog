# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::FunnelDefinition do
  def definition(**attributes)
    described_class.new(key: "talks", title: "Reading to watching", steps_attributes: [
      {name: "Visited the blog", event: "session_start"},
      {name: "Watched a talk", event: "video_start", paths_list: "/talks/, /videos/ ,"}
    ], **attributes)
  end

  it "seeds the blog's funnels only while none are stored" do
    expect(described_class.all_or_defaults.map(&:key)).to eq(%w[newsletter contact share resume])
    described_class.find_by(key: "share").destroy

    expect(described_class.all_or_defaults.map(&:key)).to eq(%w[newsletter contact resume])
  end

  it "keeps a server-sent conversion off the live site's hostname" do
    newsletter, _, share = described_class.all_or_defaults

    expect(newsletter.steps.map(&:site)).to eq([true, true, false])
    expect(newsletter).to be_server_sent
    expect(share).not_to be_server_sent
  end

  it "takes path prefixes as a list, and leaves blank steps out" do
    record = definition(steps_attributes: [{name: "Visited the blog", event: "session_start"}, {name: " ", event: "", path: ""},
      {name: "Watched a talk", event: "video_start", paths_list: "/talks/, /videos/ ,"}])

    expect(record).to be_valid
    expect(record.steps.size).to eq(2)
    expect(record.steps.last.paths).to eq(%w[/talks/ /videos/])
    expect(record.steps.last.paths_list).to eq("/talks/, /videos/")
  end

  it "refuses a funnel GA couldn't run" do
    record = definition(key: "Not A Key", steps_attributes: [{name: "Only", event: "page view", path: "contact", paths_list: "post/"}])

    expect(record).not_to be_valid
    expect(record.errors[:key]).to eq(["must be lowercase words joined by hyphens"])
    expect(record.errors[:steps]).to include("need at least two, or there's nothing to drop out between")
    step = record.steps.first
    step.valid?
    expect(step.errors.messages.slice(:event, :path, :paths_list))
      .to eq(event: ["must be a GA event name, like page_view"], path: ["must start with /"], paths_list: ["must each start with /"])
  end

  it "changes its cache version with any step" do
    record = definition.tap(&:save!)
    version = record.cache_version
    record.update!(steps_attributes: [{id: record.steps.first.id, name: "Opened the blog"}])

    expect(record.reload.cache_version).not_to eq(version)
  end
end
