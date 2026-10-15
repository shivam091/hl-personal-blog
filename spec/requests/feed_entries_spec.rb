# encoding: UTF-8

require "rails_helper"

RSpec.describe "Feed entries", type: :request do
  def entry(url, type: "post", tags: [], categories: [], **attributes)
    FeedEntry::Source.new(label: url, url: url, name: "Entry #{url[/\w+\z/]}", type: type,
      published_at: Time.utc(2026, 7, 5), last_modified_at: Time.utc(2026, 7, 5), tags: tags, categories: categories,
      **attributes)
  end

  let(:entries) do
    FeedEntry.import([
      entry("https://example.com/post/grid", tags: %w[css layout], categories: %w[CSS]),
      entry("https://example.com/tutorial/canvas", type: "tutorial", tags: %w[javascript], categories: %w[JavaScript])
    ])
  end

  def listed_urls
    response.body.scan(%r{https://example\.com/[\w/]+}).uniq
  end

  describe "showing" do
    let(:grid) { entries; FeedEntry.find("https://example.com/post/grid") }

    it "shows an entry with its type, tags, and categories linking to the filtered list" do
      get feed_entry_path(grid)

      expect(response).to have_http_status(:ok)
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("h1").text.strip).to eq("Entry grid")
      expect(page.at_css("a[href='#{grid.url}']")).to be_present
      expect(page.css("#entry ~ dl a").map { |link| [link.text, link["href"]] }).to eq([
        ["Post", feed_entries_path(type: "post")], ["CSS", feed_entries_path(category: "CSS")],
        ["css", feed_entries_path(tag: "css")], ["layout", feed_entries_path(tag: "layout")]
      ])
    end

    it "links each listed title to its entry's page" do
      grid
      get feed_entries_path(type: "post")

      expect(Nokogiri::HTML5(response.body).at_css("a[href='#{feed_entry_path(grid)}']").text.strip).to eq("Entry grid")
    end
  end

  describe "GET /feed-entries" do
    it "lists entries with their type, tags, and categories, filterable by type" do
      entries

      get feed_entries_path
      expect(response).to have_http_status(:ok)
      row = Nokogiri::HTML5(response.body).at_css("tbody tr")
      expect(row.css("a:not([target=_blank])").map { |link| link.text.strip }).to eq(["Entry grid", "Post", "CSS", "css", "layout"])
      expect(row.at_css("a[target=_blank]")["href"]).to eq("https://example.com/post/grid")

      get feed_entries_path(type: "tutorial")
      expect(listed_urls).to eq(%w[https://example.com/tutorial/canvas])
    end

    it "charts delivered and undelivered emails for finished sends, oldest first" do
      entries
      FeedEntry.find("https://example.com/post/grid").set(notified_at: 2.days.ago, notified_count: 8,
        notification_failures: [{"email" => "a@example.com"}, {"email" => "b@example.com"}])
      FeedEntry.find("https://example.com/tutorial/canvas").set(notified_at: 1.day.ago, notified_count: 10)

      get feed_entries_path

      tips = Nokogiri::HTML5(response.body).css("#deliveries ~ div g[data-tip]").map { |bar| JSON.parse(bar["data-tip"]) }
      expect(tips.map { |tip| [tip["title"], tip["rows"].map { |row| row["value"] }] }).to eq([["Entry grid", %w[8 2]], ["Entry canvas", %w[10 0]]])
    end

    it "offers no way to add, edit, delete, or import entries" do
      entries

      get feed_entries_path

      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("tbody input[name=_method][value=delete]")).to be_nil
      expect(page.at_css("input[type=file]")).to be_nil
      expect(Rails.application.routes.recognize_path("/feed-entries/new")).to include(action: "show")
      [[:post, "/feed-entries"], [:patch, "/feed-entries/x"], [:delete, "/feed-entries/x"], [:post, "/feed-entries/import"]].each do |method, path|
        expect { Rails.application.routes.recognize_path(path, method: method) }.to raise_error(ActionController::RoutingError), "#{method} #{path}"
      end
    end

    it "shows an empty state" do
      get feed_entries_path
      expect(response.body).to include("No feed entries yet.")
    end

    it "filters by tag and category, picked from the names that exist" do
      entries

      get feed_entries_path(tag: "layout")
      expect(listed_urls).to eq(%w[https://example.com/post/grid])
      expect(response.body).to include("Tag: layout")
      select = Nokogiri::HTML5(response.body).at_css("select#tag")
      expect(select.css("option").map(&:text)).to eq(%w[Any css javascript layout])
      expect(select.at_css("option[selected]").text).to eq("layout")

      get feed_entries_path(category: "JavaScript")
      expect(listed_urls).to eq(%w[https://example.com/tutorial/canvas])

      get feed_entries_path(tag: "nonexistent")
      expect(response.body).to include("No feed entries match.")
    end

    it "links each tag and category to its filter, keeping the rest of the list state" do
      entries

      get feed_entries_path(type: "post", sort: "name", direction: "asc")

      expect(response.body).to include("/feed-entries?direction=asc&amp;sort=name&amp;tag=layout&amp;type=post")
    end

    context "with more entries than fit on one page" do
      before do
        FeedEntry.import((1..30).map do |n|
          entry(format("https://example.com/post/%02d", n), type: n.even? ? "post" : "snippet",
            published_at: Time.utc(2026, 9, n), last_modified_at: Time.utc(2026, 9, n))
        end)
      end

      it "paginates on the server, newest first" do
        get feed_entries_path(page: 2)

        expect(listed_urls).to eq(%w[https://example.com/post/05 https://example.com/post/04 https://example.com/post/03 https://example.com/post/02 https://example.com/post/01])
        expect(response.body).to include("26–30", 'rel="prev"')
      end

      it "sorts by a column and direction, carrying them into page links" do
        get feed_entries_path(sort: "name", direction: "asc")

        expect(listed_urls.first(2)).to eq(%w[https://example.com/post/01 https://example.com/post/02])
        expect(response.body).to include('aria-sort="ascending"')
        expect(response.body).to include("/feed-entries?direction=asc&amp;page=2&amp;sort=name")
      end

      it "ignores unknown sort columns" do
        get feed_entries_path(sort: "$where", direction: "sideways")

        expect(response).to have_http_status(:ok)
        expect(listed_urls.first).to eq("https://example.com/post/30")
      end

      it "searches by title, URL, and date ranges, with the panel open" do
        get feed_entries_path(q: "entry 1", link: "/post/", published_from: "2026-09-12", updated_to: "2026-09-14")

        expect(listed_urls).to eq(%w[https://example.com/post/14 https://example.com/post/13 https://example.com/post/12])
        expect(Nokogiri::HTML5(response.body).at_css("main details")["open"]).not_to be_nil
        expect(response.body).to include("Title contains “entry 1”", "URL contains “/post/”", "Published from 12 Sep, 2026", "Updated to 14 Sep, 2026")
      end

      it "treats search text literally, not as a regex" do
        get feed_entries_path(link: ".*")

        expect(response.body).to include("No feed entries match.")
      end

      it "counts each type tab within the current search" do
        get feed_entries_path(q: "entry 1")

        expect(response.body).to match(%r{All\s*<span[^>]*>10</span>})
        expect(response.body).to match(%r{Posts\s*<span[^>]*>5</span>})
        expect(response.body).to match(%r{Snippets\s*<span[^>]*>5</span>})
      end

      it "exports every matching entry, not just the current page" do
        get feed_entries_path(format: :csv, link: "/post/", page: 2)

        expect(response.body.lines.size).to eq(31), "the header and 30 rows"
      end
    end

    it "exports the filtered entries as CSV" do
      entries

      get feed_entries_path(format: :csv, type: "post")

      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("feed-entries-")
      expect(response.body).to eq(<<~CSV)
        #,URL,Title,Description,Type,Published,Updated,Tags,Categories
        1,https://example.com/post/grid,Entry grid,,post,2026-07-05T00:00:00.000Z,2026-07-05T00:00:00.000Z,"css, layout",CSS
      CSV
    end
  end

  describe "POST /feed-entries/sync" do
    it "queues a feed sync from the list" do
      get feed_entries_path
      expect(response.body).to include("Sync feed")

      expect { post sync_feed_entries_path }.to change(SyncRequest, :count).by(1)
      expect(SyncFeedJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(kind: "feed", trigger: "admin").id.to_s)
      expect(response).to redirect_to(feed_entries_path)
      expect(flash[:notice]).to start_with("Syncing from the Atom feed in the background.")
    end
  end

  describe "sync requests" do
    it "shows when the feed was last synced" do
      travel_to(Time.zone.local(2026, 10, 12, 12)) do
        SyncRequest.create!(kind: "feed", status: "succeeded", finished_at: 3.hours.ago, created_at: 3.hours.ago)
        get feed_entries_path
      end

      line = Nokogiri::HTML5(response.body).at_css("#last-sync")
      expect(line.text.squish).to include("Last synced 12 Oct, 2026 09:00")
      expect(line.at_css("a")["href"]).to eq(sync_requests_path(section: "feed"))
    end

    it "resyncs with the feed's own job" do
      post resync_sync_request_path(SyncRequest.create!(kind: "feed", status: "failed"))

      expect(SyncFeedJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(trigger: "resync").id.to_s)
    end

    it "records a job's sync, or updates the request it was enqueued for" do
      allow(FeedSyncService).to receive(:call) { SyncResult.new(1, 0, 0, []) }
      request = SyncRequest.enqueue("feed")

      SyncFeedJob.perform_now(request_id: request.id.to_s)
      SyncFeedJob.perform_now

      expect(request.reload).to have_attributes(status: "succeeded", created_count: 1)
      expect(SyncRequest.find_by(kind: "feed", trigger: "job").status).to eq("succeeded")
    end
  end
end
