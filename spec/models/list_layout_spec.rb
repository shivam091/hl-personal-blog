# encoding: UTF-8

require "rails_helper"

RSpec.describe ListLayout do
  let(:definition) do
    {label: "Pages", route: "crawled_pages", sort: "url",
     columns: {url: {label: "URL", sort: "asc", required: true}, last_modified_at: {label: "Last modified", sort: "desc"},
               indexed: {label: "Indexed", sort: "desc"}, notes: {label: "Notes"}}}
  end

  def layout(setting = nil)
    ListLayout.new("crawled_pages", definition, setting)
  end

  def keys(columns)
    columns.map(&:key)
  end

  it "follows the file's order and sort until customized" do
    expect(keys(layout.visible_columns)).to eq(%w[url last_modified_at indexed notes])
    expect(layout.default_sort).to eq(%w[url asc])
    expect(keys(layout.sortable_columns)).to eq(%w[url last_modified_at indexed])
    expect(layout).not_to be_customized
  end

  it "lays a saved order, hidden columns, sort and page size over the file" do
    setting = ListSetting.new(list: "crawled_pages", order: %w[indexed url last_modified_at notes], hidden: %w[notes],
      sort: "indexed", direction: "asc", per_page: 100)

    expect(keys(layout(setting).visible_columns)).to eq(%w[indexed url last_modified_at])
    expect(keys(layout(setting).hidden_columns)).to eq(%w[notes])
    expect(layout(setting).default_sort).to eq(%w[indexed asc])
    expect(layout(setting).default_per_page).to eq(100)
  end

  it "survives columns being added to or dropped from the file since saving" do
    setting = ListSetting.new(list: "crawled_pages", order: %w[gone indexed url], hidden: %w[gone], sort: "gone")

    expect(keys(layout(setting).visible_columns)).to eq(%w[indexed url last_modified_at notes])
    expect(layout(setting).default_sort).to eq(%w[url asc])
  end

  it "never hides a required column" do
    setting = ListSetting.new(list: "crawled_pages", hidden: %w[url indexed])

    expect(keys(layout(setting).visible_columns)).to eq(%w[url last_modified_at notes])
  end

  describe "#save" do
    it "keeps only known columns, sorts and page sizes" do
      saved = layout
      saved.save(shown: %w[indexed url $where], hidden: %w[last_modified_at url], sort: "notes", direction: "up", per_page: "7")

      setting = ListSetting.find_by(list: "crawled_pages")
      expect(setting.order).to eq(%w[indexed url last_modified_at notes])
      expect(setting.hidden).to eq(%w[last_modified_at])
      expect([setting.sort, setting.direction, setting.per_page]).to eq([nil, nil, nil])
      expect(keys(saved.visible_columns)).to eq(%w[indexed url notes])
    end

    it "stores nothing when the choice is the file's own default" do
      ListSetting.create!(list: "crawled_pages", hidden: %w[notes])
      saved = ListLayout.new("crawled_pages", definition, ListSetting.first)

      saved.save(shown: %w[url last_modified_at indexed notes], hidden: [], sort: "url", direction: "asc", per_page: "25")

      expect(ListSetting.count).to eq(0)
      expect(saved).not_to be_customized
    end
  end

  it "defines every list against a real route, with a sortable default" do
    ListLayout.all.each do |list|
      expect(Rails.application.routes.url_helpers).to respond_to(:"#{list.route}_path"), "no route named #{list.route}"
      expect(list.sortable_columns.map(&:key)).to include(list.default_sort.first)
      expect(list.columns.select(&:required)).to be_present, "#{list.key} has no required column"
    end
  end
end
