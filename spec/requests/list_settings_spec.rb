# encoding: UTF-8

require "rails_helper"

RSpec.describe "List settings", type: :request do
  let!(:page) { CrawledPage.create!(url: "https://example.com/a", indexed: true, last_modified_at: Time.utc(2026, 7, 5)) }

  def headers
    Nokogiri::HTML5(response.body).css("thead th").map { |th| th.text.squish }.compact_blank
  end

  it "lists every list's layout" do
    get list_settings_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Crawled pages", "URL, ascending", "Default")
  end

  it "opens the dialog with each column in its zone" do
    ListSetting.create!(list: "crawled_pages", hidden: %w[indexed])

    get edit_list_setting_path("crawled_pages")

    html = Nokogiri::HTML5(response.body)
    expect(html.css("[data-zone=shown] input").map { |input| input["value"] }).to eq(%w[url last_modified_at])
    expect(html.css("[data-zone=hidden] input").map { |input| input["name"] }).to eq(%w[hidden[]])
  end

  it "404s for an unknown list" do
    get edit_list_setting_path("nope")

    expect(response).to have_http_status(:not_found)
  end

  it "reorders, hides and sorts a list, then resets it" do
    patch list_setting_path("crawled_pages"), params: {shown: %w[indexed url], hidden: %w[last_modified_at], sort: "indexed", direction: "asc", per_page: "50"},
      headers: {"HTTP_REFERER" => crawled_pages_url}
    expect(response).to redirect_to(crawled_pages_url)

    get crawled_pages_path
    expect(headers).to eq(%w[# Indexed URL Actions])
    expect(response.body).to include('aria-sort="ascending"')

    get list_settings_path
    expect(response.body).to include("Customized", "Indexed, ascending")

    delete list_setting_path("crawled_pages")
    expect(ListSetting.count).to eq(0)

    get crawled_pages_path
    expect(headers).to eq(["#", "URL", "Last modified", "Indexed", "Actions"])
  end

  it "opens a list on its default tab, dense, without row numbers and with a fixed header" do
    CrawledPage.create!(url: "https://example.com/b", indexed: false, last_modified_at: Time.utc(2026, 7, 5))
    patch list_setting_path("crawled_pages"), params: {tab: "no", density: "compact", row_numbers: "0", sticky_header: "1"}

    get crawled_pages_path
    html = Nokogiri::HTML5(response.body)
    expect(response.body).to include("https://example.com/b")
    expect(response.body).not_to include("https://example.com/a\"")
    expect(html.at_css("nav[aria-label='Filter by indexed status'] a[aria-current=page]").text).to include("Not indexed")
    expect(html.at_css("nav a[href='/crawled-pages?indexed=all']")).to be_present
    expect(headers).to eq(%w[URL Last\ modified Indexed Actions])
    expect(html.at_css("thead")["class"]).to include("sticky")
    expect(html.at_css("table")["class"]).to include("[&_td]:py-1")

    get crawled_pages_path(indexed: "all")
    expect(response.body).to include("https://example.com/a", "https://example.com/b")
  end

  describe "saved searches" do
    it "saves the current search, links to it and removes it" do
      get crawled_pages_path(q: "example", sort: "indexed", direction: "asc")
      expect(response.body).to include("Save search")

      post saved_searches_path, params: {list: "crawled_pages", name: "  Examples ", query: "direction=asc&q=example&sort=indexed"},
        headers: {"HTTP_REFERER" => crawled_pages_url}
      expect(response).to redirect_to(crawled_pages_url)
      search = SavedSearch.find_by(name: "Examples")

      get crawled_pages_path
      expect(Nokogiri::HTML5(response.body).at_css("a[href='/crawled-pages?direction=asc&q=example&sort=indexed']").text).to eq("Examples")

      get crawled_pages_path(q: "example", sort: "indexed", direction: "asc")
      expect(response.body).not_to include("Save search")

      delete saved_search_path(search)
      expect(SavedSearch.count).to eq(0)
    end

    it "drops query values that aren't plain strings" do
      search = SavedSearch.new(query: "q=a&host[]=evil.example")

      expect(search.params).to eq("q" => "a")
    end

    it "refuses a list that doesn't exist" do
      post saved_searches_path, params: {list: "nope", name: "x", query: "q=a"}

      expect(SavedSearch.count).to eq(0)
      expect(flash[:alert]).to include("Couldn't save")
    end
  end
end
