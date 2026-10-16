# encoding: UTF-8

require "rails_helper"

RSpec.describe "Page likes", type: :request do
  # Shaped like the frontend writes them, so the page reads real data.
  before do
    PageLike.collection.insert_many((1..30).map do |n|
      slug = format("/post/%02d", n)
      {"_id" => slug, "slug" => slug, "url" => "https://blog.example.com#{slug}", "likeCount" => n, "createdAt" => Time.utc(2026, 8, n), "updatedAt" => Time.utc(2026, 9, n)}
    end)
  end

  def slugs
    response.body.scan(%r{/post/\d+}).uniq
  end

  it "lists pages most liked first, paginated on the server" do
    get page_likes_path

    expect(response).to have_http_status(:ok)
    expect(slugs.first(3)).to eq(%w[/post/30 /post/29 /post/28])
    page = Nokogiri::HTML5(response.body)
    expect(page.css("thead th").map { |th| th.text.strip }.second).to eq("#")
    expect(page.at_css("tbody a[href='#{page_like_path("/post/30")}']").text).to eq("https://blog.example.com/post/30")
    expect(page.at_css("tbody a[href='https://blog.example.com/post/30']")["target"]).to eq("_blank")

    get page_likes_path(page: 2)
    expect(slugs).to eq(%w[/post/05 /post/04 /post/03 /post/02 /post/01])
  end

  it "searches by URL and by when it was last liked" do
    get page_likes_path(q: "/post/1")
    expect(slugs).to all(start_with("/post/1"))

    get page_likes_path(liked_from: "2026-09-29")
    expect(slugs).to contain_exactly("/post/29", "/post/30")
  end

  it "sorts by URL" do
    get page_likes_path(sort: "url", direction: "asc")
    expect(slugs.first(2)).to eq(%w[/post/01 /post/02])
  end

  it "exports every matching page as CSV, not just the current one" do
    get page_likes_path(format: :csv, q: "/post/1")

    expect(response.media_type).to eq("text/csv")
    rows = CSV.parse(response.body)
    expect(rows.first).to eq(PageLike::CSV_HEADERS)
    expect(rows.drop(1).map(&:first)).to eq((10..19).reverse_each.map { |n| "https://blog.example.com/post/#{n}" })
  end

  it "counts likes in a picked span from each page's days, sorting by them" do
    PageLike.collection.update_one({"_id" => "/post/01"}, {"$set" => {"countriesByDay" => {"2026-10-10" => {"IN" => 4, "US" => 1}}}})
    PageLike.collection.update_one({"_id" => "/post/02"}, {"$set" => {"countriesByDay" => {"2026-10-10" => {"IN" => 2}, "2026-09-01" => {"IN" => 9}}}})

    get page_likes_path(from: "2026-10-01", to: "2026-10-11")

    expect(slugs.first(2)).to eq(%w[/post/01 /post/02])
    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("tbody tr td:nth-child(4)").text).to eq("5")
    expect(page.at_css("[aria-controls=period-menu]").text.squish).to eq("Period: Custom")

    get page_likes_path(from: "2026-10-01", to: "2026-10-11", sort: "like_count", direction: "asc")
    expect(slugs.first(2)).to eq(%w[/post/03 /post/04])

    get page_likes_path(format: :csv, from: "2026-10-01", to: "2026-10-11", q: "/post/0")
    expect(CSV.parse(response.body).second).to eq(["https://blog.example.com/post/01", "5", "IN: 4; US: 1", "2026-08-01T00:00:00.000Z", "2026-09-01T00:00:00.000Z"])
  end

  it "shows an empty state" do
    PageLike.delete_all
    get page_likes_path
    expect(response.body).to include("No page likes yet.")
  end

  it "shows a page's likes by day with their countries" do
    PageLike.collection.update_one({"_id" => "/post/30"}, {"$set" => {"countriesByDay" => {"2026-09-29" => {"IN" => 2}, "2026-09-30" => {"US" => 1}}}})

    get page_like_path("/post/30")

    expect(response).to have_http_status(:ok)
    page = Nokogiri::HTML5(response.body)
    days = page.css("#likes-by-day ~ div tbody tr").map { |tr| tr.css("td").map { |td| td.text.squish } }
    expect(days).to eq([["30 Sep, 2026", "1", "US 1"], ["29 Sep, 2026", "2", "IN 2"]])
    expect(response.body).to include("66.7%")
  end
end
