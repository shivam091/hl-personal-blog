# encoding: UTF-8

require "rails_helper"

RSpec.describe "Icons", type: :request do
  let(:sprite) { Nokogiri::XML(Rails.root.join("app/assets/images/icons.svg").read) }
  let(:symbols) { sprite.css("symbol").map { |symbol| symbol["id"] } }

  it "is a valid sprite with unique symbols" do
    expect(sprite.errors).to be_empty
    expect(symbols).to eq(symbols.uniq)
  end

  # A missing symbol renders as blank space, with no error anywhere.
  it "only uses icons the sprite has" do
    CrawledPage.create!(url: "https://example.com/a", indexed: true, last_modified_at: Time.utc(2026, 7, 5))
    CrawledPage.create!(url: "https://example.com/b", last_modified_at: Time.utc(2026, 7, 5))

    get crawled_pages_path

    used = Nokogiri::HTML5(response.body).css("svg use").map { |use| use["href"].split("#").last }
    expect(used).not_to be_empty
    expect(used.uniq - symbols).to be_empty
  end

  it "shows table controls as icons only, still named for screen readers" do
    page = CrawledPage.create!(url: "https://example.com/a", indexed: true, last_modified_at: Time.utc(2026, 7, 5))

    get crawled_pages_path

    row = Nokogiri::HTML5(response.body).at_css("tbody tr")
    inspect = row.at_css("form[action='#{inspect_url_crawled_page_path(page)}'] button")
    expect(inspect.text.strip).to be_empty
    expect(inspect["aria-label"]).to eq("Inspect #{page.url} now")
    expect(row.at_css("svg[role=img]")["aria-label"]).to eq("Indexed")
    expect(row.text).not_to include("Yes")
  end
end
