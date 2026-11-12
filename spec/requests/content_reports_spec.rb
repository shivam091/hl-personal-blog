# encoding: UTF-8

require "rails_helper"

RSpec.describe "Content report", type: :request do
  around { |example| travel_to(Time.zone.parse("2026-10-12 12:00")) { example.run } }

  def page
    Nokogiri::HTML5(response.body)
  end

  before do
    FeedEntry.create!(
      url: "https://blog.example.com/post/a",
      name: "A post",
      type: "post",
      published_at: Time.zone.parse("2026-10-01"),
      last_modified_at: Time.zone.parse("2026-10-01")
    )
    PageView.collection.insert_one(
      "_id" => "/post/a",
      "slug" => "/post/a",
      "countriesByDay" => {"2026-10-10" => {"IN" => 30}}
    )
  end

  it "compares types and follows entries from publishing to being read" do
    get content_report_path

    expect(response).to have_http_status(:ok)
    expect(page.at_css("#by-type ~ div tbody tr").css("td").map(&:text)).to eq(%w[Posts 1 1 30 30.0 0 0])
    expect(page.css("#seo-funnel ~ div li span.font-medium").map(&:text)).to include("Published", "Read")
  end

  it "totals each type's AI impressions from the latest upload, once there is one" do
    Google::SearchConsole::GenerativeAiStat.create!(search_type: "Web", date: Date.new(2026, 9, 1), impressions: 9)
    Google::SearchConsole::GenerativeAiRow.create!(search_type: "Web", from: Date.new(2026, 9, 1), to: Date.new(2026, 9, 30),
      breakdown: "pages", label: "https://blog.example.com/post/a", impressions: 9)

    get content_report_path

    expect(page.css("#by-type ~ div thead th").last.text.squish).to eq("AI impressions")
    expect(page.at_css("#by-type ~ div tbody tr").css("td").map(&:text)).to eq(%w[Posts 1 1 30 30.0 0 0 9])
  end

  it "plots each entry's views against its age" do
    get content_report_path

    tip = JSON.parse(page.at_css("section[aria-labelledby=decay] span[data-tip]")["data-tip"])
    expect(tip["title"]).to eq("A post")
    expect(tip["rows"].map { |row| row["value"] }).to eq(["30", "1 Oct, 2026", "Post"])
  end

  it "plots six months of age unless another span is picked" do
    get content_report_path

    expect(page.at_css("select#decay-months option[selected]")["value"]).to eq("6")
    expect(page.at_css("section[aria-labelledby=decay]").text.squish).to include("over its first 6 months")

    get content_report_path(decay_months: "12")
    expect(page.at_css("select#decay-months option[selected]")["value"]).to eq("12")
    expect(page.at_css("section[aria-labelledby=decay]").text.squish).to include("over its first 12 months")

    get content_report_path(decay_months: "7")
    expect(page.at_css("select#decay-months option[selected]")["value"]).to eq("6")
  end

  it "ranks tags by views per entry" do
    css = Tag.create!(name: "css")
    FeedEntry.find("https://blog.example.com/post/a").update!(tags: [css])

    get content_report_path

    bar = JSON.parse(page.at_css("#tags ~ div li[data-tip]")["data-tip"])
    expect([bar["title"], bar["rows"].first["value"]]).to eq(["css", "30"])
  end

  def calendar
    page.at_css("section[aria-labelledby=calendar]")
  end

  def gaps_card
    page.at_css("section[aria-labelledby=gaps]")
  end

  it "marks each day of the last twelve months with what was published on it" do
    get content_report_path

    days = calendar.css("span[data-tip]").map { |cell| JSON.parse(cell["data-tip"]) }
    expect(days.size).to eq(346)
    published = days.find { |day| day["title"] == "Thu, 1 Oct 2026" }
    expect(published["rows"]).to eq([{"value" => "1", "name" => "Entries"}, {"value" => "Post", "name" => "A post"}])
    expect(calendar.text.squish).to include("1 entry on 1 day since 1 Nov, 2025")
  end

  it "labels every month of the calendar, the first included" do
    get content_report_path

    labels = calendar.css(".grid > span.h-4").map(&:text).compact_blank
    expect(labels).to eq(%w[Nov Dec Jan Feb Mar Apr May Jun Jul Aug Sep Oct])
  end

  it "narrows the calendar to one type of entry" do
    FeedEntry.create!(url: "https://blog.example.com/post/tip", name: "A tip", type: "snippet",
      published_at: Time.zone.parse("2026-10-05"), last_modified_at: Time.zone.parse("2026-10-05"))

    get content_report_path(calendar_type: "snippet")

    expect(page.css("#calendar-type option").map { |option| [option.text, option["selected"].present?] })
      .to eq([["All entries", false], ["Posts", false], ["Tutorials", false], ["Snippets", true], ["Series", false]])
    titles = calendar.css("span[data-tip]").map { |cell| JSON.parse(cell["data-tip"]) }.reject { |day| day["rows"].first["value"] == "0" }.map { |day| day["title"] }
    expect(titles).to eq(["Mon, 5 Oct 2026"])
    expect(calendar.text.squish).to include("1 snippet on 1 day since 1 Nov, 2025. Only snippets, whatever the period.")

    get content_report_path(calendar_type: "$where")
    expect(calendar.text.squish).to include("2 entries on 2 days since 1 Nov, 2025. Every entry")
  end

  it "explains each of the days between entries figures" do
    get content_report_path

    hints = gaps_card.css("[role=tooltip]").map { |hint| hint.text.squish }
    expect(hints.size).to eq(5)
    expect(hints.last).to include("drops to 0 only once a whole week passes")
  end

  it "charts the waits between publishing days, with the longest gap and streaks" do
    FeedEntry.create!(url: "https://blog.example.com/post/z", name: "Z post", type: "post",
      published_at: Time.zone.parse("2026-09-21"), last_modified_at: Time.zone.parse("2026-09-21"))

    get content_report_path

    card = gaps_card
    figures = card.css("dl > div").map { |figure| figure.dup.tap { |copy| copy.css("[role=tooltip]").each(&:remove) }.text.squish }
    expect(figures).to eq([
      "Since the last entry 11 days 1 Oct, 2026",
      "Typical gap 10 days The median wait",
      "Longest gap 10 days 21 Sep, 2026 – 1 Oct, 2026",
      "Longest streak 2 weeks From the week of 21 Sep, 2026",
      "Current streak 0 weeks With an entry every week"
    ])
    bar = JSON.parse(card.at_css("g[data-tip]")["data-tip"])
    expect([bar["title"], bar["rows"].first["value"]]).to eq(["Thu, 1 Oct 2026", "10"])
  end

  it "narrows the days between entries to one type of entry" do
    FeedEntry.create!(url: "https://blog.example.com/post/tip", name: "A tip", type: "snippet",
      published_at: Time.zone.parse("2026-10-05"), last_modified_at: Time.zone.parse("2026-10-05"))

    get content_report_path(gaps_type: "snippet")

    card = gaps_card
    expect(page.css("#gaps-type option").map { |option| [option.text, option["selected"].present?] })
      .to eq([["All entries", false], ["Posts", false], ["Tutorials", false], ["Snippets", true], ["Series", false]])
    expect(card.at_css("dl > div dd").text.squish).to eq("7 days")
    expect(card.text.squish).to include("No two publishing days in the last year", "Only snippets, whatever the period.")

    get content_report_path(gaps_type: "tutorial")
    expect(gaps_card.text.squish).to include("No tutorials published yet.")

    get content_report_path(gaps_type: "$where")
    expect(gaps_card.text.squish).to include("Every entry, whatever the period.")
  end

  it "ranks categories by views per entry, holding back clicks until Search Console has synced" do
    web = Category.create!(name: "Web")
    FeedEntry.find("https://blog.example.com/post/a").update!(categories: [web])

    get content_report_path

    bar = JSON.parse(page.at_css("#categories ~ div li[data-tip]")["data-tip"])
    expect([bar["title"], bar["rows"].first["value"]]).to eq(["Web", "30"])
    expect(page.css("#categories ~ div tbody tr td").map { |cell| cell.text.strip }).to eq(["Web", "1", "30", "—", "—", "—"])
  end

  it "shows how long after publishing entries were updated" do
    FeedEntry.find("https://blog.example.com/post/a").update!(last_modified_at: Time.zone.parse("2026-10-05"))

    get content_report_path

    card = page.at_css("#updates").parent
    expect(card.text.squish).to include("1 of 1 entry updated after the day they went out, typically 4 days later.")
    band = JSON.parse(card.css("li[data-tip]")[1]["data-tip"])
    expect([band["title"], band["rows"].first["value"]]).to eq(["Within a week", "1"])
    expect(card.css("tbody td").map { |cell| cell.text.strip }).to eq(["A post", "1 Oct, 2026", "5 Oct, 2026"])
  end

  it "exports every entry as CSV" do
    get content_report_path(format: :csv)

    rows = CSV.parse(response.body)
    expect(rows.first).to eq(ContentStats::CSV_HEADERS)
    expect(rows.second.values_at(0, 2, 5, 9)).to eq(["https://blog.example.com/post/a", "post", "30", "No"])
  end

  context "with Search Console and Analytics figures" do
    before do
      FeedEntry.create!(
        url: "https://blog.example.com/post/b",
        name: "B post",
        type: "post",
        published_at: Time.zone.parse("2026-06-01"),
        last_modified_at: Time.zone.parse("2026-06-01")
      )
      Google::SearchConsole::Stat.create!(
        date: Date.new(2026, 10, 8),
        page: "https://blog.example.com/post/a",
        page_path: "/post/a",
        clicks: 15,
        impressions: 300,
        position: 5.0
      )
      Google::Analytics::SourceStat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/a",
        channel_group: "Organic Search",
        source: "google",
        medium: "organic",
        sessions: 15,
        engaged_sessions: 3
      )
      Google::Analytics::SourceStat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/other",
        channel_group: "Organic Search",
        source: "google",
        medium: "organic",
        sessions: 15,
        engaged_sessions: 15
      )
      Google::Analytics::Stat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/a",
        views: 30,
        active_users: 10,
        engagement_seconds: 900
      )
      Google::Analytics::EventStat.create!(
        date: Date.new(2026, 10, 8),
        page_path: "/post/a",
        event_name: "scroll",
        event_count: 12
      )
    end

    it "lists entries not shown in search, search readers who don't stay, and how far readers get" do
      get content_report_path

      cells = ->(id) { page.css("##{id} ~ div table tbody tr").map { |row| row.css("td").map { |td| td.text.squish } } }
      expect(cells.("not-in-search")).to eq([["B post", "Not in the sitemap", I18n.l(Date.new(2026, 6, 1))]])
      expect(cells.("search-leaks")).to eq([["A post", "15", "15", "20%", "0s"]])
      expect(cells.("reading")).to eq([["A post", "30", "1m 30s", "40.0%"]])
    end

    it "gives each category's search clicks, in all and per entry" do
      web = Category.create!(name: "Web")
      FeedEntry.where(:_id.in => ["https://blog.example.com/post/a", "https://blog.example.com/post/b"]).each do |entry|
        entry.update!(categories: [web])
      end

      get content_report_path

      expect(page.css("#categories ~ div tbody tr td").map { |cell| cell.text.strip }.last(2)).to eq(["15", "7.5"])
    end

    it "exports each list as CSV" do
      get content_report_path(format: :csv, export: "not-in-search")
      expect(CSV.parse(response.body).drop(1).map(&:first)).to eq(["https://blog.example.com/post/b"])

      get content_report_path(format: :csv, export: "search-readers")
      expect(CSV.parse(response.body).second.values_at(0, 2, 4, 7)).to eq(["https://blog.example.com/post/a", "15", "15", "Yes"])

      get content_report_path(format: :csv, export: "reading")
      expect(CSV.parse(response.body).second).to eq(["https://blog.example.com/post/a", "A post", "30", "90.0", "0.4"])
    end
  end

  it "keeps the country filter but leaves comparison off, since nothing on it is compared" do
    get content_report_path

    page = Nokogiri::HTML5(response.body)
    expect(page.at_css("[aria-controls=period-compare]")).to be_nil
    expect(page.at_css("[aria-controls=period-country]")).to be_present
  end
end
