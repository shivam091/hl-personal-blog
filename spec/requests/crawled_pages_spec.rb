# encoding: UTF-8

require "rails_helper"

RSpec.describe "Crawled pages", type: :request do
  let(:indexed) { CrawledPage.create!(url: "https://example.com/indexed", indexed: true, last_modified_at: Time.utc(2026, 7, 5)) }
  let(:not_indexed) { CrawledPage.create!(url: "https://example.com/not-indexed", last_modified_at: Time.utc(2026, 7, 5)) }

  describe "GET /crawled_pages" do
    it "lists pages, filterable by indexed status" do
      indexed && not_indexed

      get crawled_pages_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(indexed.url, not_indexed.url)

      get crawled_pages_path(indexed: "no")
      expect(response.body).to include(not_indexed.url)
      expect(response.body).not_to include(indexed.url)
    end

    it "shows an empty state" do
      get crawled_pages_path
      expect(response.body).to include("No crawled pages yet.")
    end

    it "offers no way to add, edit, or import pages, since they come from the sitemap" do
      not_indexed

      get crawled_pages_path

      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("input[type=file]")).to be_nil
      expect(page.at_css("tbody a[href$='/edit']")).to be_nil
      [[:get, "/crawled-pages/new"], [:post, "/crawled-pages"], [:get, "/crawled-pages/x/edit"], [:patch, "/crawled-pages/x"], [:post, "/crawled-pages/import"]].each do |method, path|
        expect { Rails.application.routes.recognize_path(path, method: method) }.to raise_error(ActionController::RoutingError), "#{method} #{path}"
      end
    end

    context "with more pages than fit on one page" do
      before do
        CrawledPage.collection.insert_many((1..30).map do |n|
          {url: format("https://example.com/%02d", n), indexed: n.even?, last_modified_at: Time.utc(2026, 9, n)}
        end)
      end

      it "paginates on the server" do
        get crawled_pages_path(page: 2)

        expect(response.body).to include("https://example.com/26", "https://example.com/30")
        expect(response.body).not_to include("https://example.com/25\"")
        expect(response.body).to include("26–30", 'rel="prev"')
      end

      it "sorts by a column and direction, carrying them into page links" do
        get crawled_pages_path(sort: "last_modified_at", direction: "desc")

        expect(response.body.index("https://example.com/30")).to be < response.body.index("https://example.com/29")
        expect(response.body).to include('aria-sort="descending"')
        expect(response.body).to include("/crawled-pages?direction=desc&amp;page=2&amp;sort=last_modified_at")
      end

      it "ignores unknown sort columns" do
        get crawled_pages_path(sort: "$where", direction: "sideways")

        expect(response).to have_http_status(:ok)
        expect(response.body.index("https://example.com/01")).to be < response.body.index("https://example.com/02")
      end

      it "searches by URL and last modified range, with the panel open" do
        get crawled_pages_path(q: "example.com/1", modified_from: "2026-09-12", modified_to: "2026-09-14")

        urls = response.body.scan(%r{https://example\.com/\d+}).uniq
        expect(urls).to eq(%w[https://example.com/12 https://example.com/13 https://example.com/14])
        expect(Nokogiri::HTML5(response.body).at_css("main details")["open"]).not_to be_nil
        expect(response.body).to include("URL contains “example.com/1”", "Last modified from 12 Sep, 2026", "Last modified to 14 Sep, 2026")
        expect(response.body).to include("/crawled-pages?modified_from=2026-09-12&amp;modified_to=2026-09-14"),
          "the chip that removes q"
      end

      it "keeps the search panel collapsed when not searching" do
        get crawled_pages_path

        expect(Nokogiri::HTML5(response.body).at_css("main details")["open"]).to be_nil
      end

      it "treats search text literally, not as a regex" do
        get crawled_pages_path(q: ".*")

        expect(response.body).to include("No crawled pages match.")
      end

      it "counts each indexed tab within the current search" do
        get crawled_pages_path(q: "example.com/1")

        expect(response.body).to match(%r{All\s*<span[^>]*>10</span>})
        expect(response.body).to match(%r{Indexed\s*<span[^>]*>5</span>})
      end

      it "switches page size, keeping the search and sort" do
        get crawled_pages_path(q: "example.com", sort: "url", direction: "desc", per_page: 50)

        expect(response.body.scan(%r{https://example\.com/\d+}).uniq.size).to eq(30)
        expect(response.body).to include("/crawled-pages?direction=desc&amp;q=example.com&amp;sort=url\""),
          "the 25 per page link"
      end

      it "exports every matching page, not just the current one" do
        get crawled_pages_path(format: :csv, q: "example.com/", page: 2)

        expect(response.body.lines.size).to eq(31), "the header and 30 rows"
      end
    end

    it "exports the filtered pages as CSV" do
      indexed && not_indexed

      get crawled_pages_path(format: :csv, indexed: "yes")

      expect(response.media_type).to eq("text/csv")
      expect(response.headers["Content-Disposition"]).to include("crawled-pages-")
      expect(response.body).to eq("#,URL,Last modified,Status\n1,https://example.com/indexed,2026-07-05T00:00:00.000Z,Yes\n")
    end
  end

  describe "POST /crawled_pages/sync" do
    it "queues a sitemap sync from the list" do
      get crawled_pages_path
      expect(response.body).to include("Sync sitemap")

      expect { post sync_crawled_pages_path }.to change(SyncRequest, :count).by(1)
      expect(SyncSitemapJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(kind: "sitemap", trigger: "admin").id.to_s)
      expect(response).to redirect_to(crawled_pages_path)
      expect(flash[:notice]).to start_with("Syncing from the sitemap in the background.")
    end
  end

  describe "PATCH /crawled_pages/request-indexing" do
    it "marks the ticked pages not yet indexed, without calling Google" do
      crawled = CrawledPage.create!(url: "https://example.com/post", last_modified_at: 1.day.ago)
      indexed = CrawledPage.create!(url: "https://example.com/old", last_modified_at: 1.day.ago, indexed: true)

      patch request_indexing_crawled_pages_path, params: {ids: [crawled.id.to_s, indexed.id.to_s]}, headers: {"HTTP_REFERER" => crawled_pages_url}

      expect(crawled.reload.index_requested_at).to be_present
      expect(indexed.reload.index_requested_at).to be_nil
      expect(flash[:notice]).to eq("Marked 1 page as requested in Search Console. Each is marked indexed once an inspection finds it in Google.")
    end

    it "moves the mark to now when a page is requested again" do
      crawled = CrawledPage.create!(url: "https://example.com/post", last_modified_at: 1.day.ago, index_requested_at: 3.days.ago)

      patch request_indexing_crawled_page_path(crawled)

      expect(crawled.reload.index_requested_at).to be_within(1.minute).of(Time.current)
    end

    it "says so when every page is already indexed" do
      indexed = CrawledPage.create!(url: "https://example.com/old", last_modified_at: 1.day.ago, indexed: true)

      patch request_indexing_crawled_page_path(indexed)

      expect(flash[:notice]).to eq("Those pages are already indexed.")
    end

    it "shows a requested page as waiting, and clears the request when it's marked indexed by hand" do
      crawled = CrawledPage.create!(url: "https://example.com/post", last_modified_at: 1.day.ago, index_requested_at: 1.hour.ago)

      get crawled_pages_path
      expect(Nokogiri::HTML5(response.body).at_css("tbody").text).to include("Requested")

      patch mark_indexed_crawled_page_path(crawled)
      expect(crawled.reload).to have_attributes(indexed: true, index_requested_at: nil)
    end
  end

  describe "PATCH /crawled_pages/:id/indexed" do
    it "offers each row the mark that would change it" do
      indexed && not_indexed

      get crawled_pages_path

      page = Nokogiri::HTML5(response.body)
      button = page.at_css("tbody form[action='#{mark_indexed_crawled_page_path(not_indexed)}'] button")
      expect(button["aria-label"]).to eq("Mark #{not_indexed.url} as indexed")
      expect(page.at_css("tbody form[action='#{mark_not_indexed_crawled_page_path(not_indexed)}']")).to be_nil
      button = page.at_css("tbody form[action='#{mark_not_indexed_crawled_page_path(indexed)}'] button")
      expect(button["aria-label"]).to eq("Mark #{indexed.url} as not indexed")
      expect(page.at_css("tbody form[action='#{mark_indexed_crawled_page_path(indexed)}']")).to be_nil
    end

    it "marks just that page and returns to the list as it was" do
      other = CrawledPage.create!(url: "https://example.com/other", last_modified_at: Time.utc(2026, 7, 5))
      list = crawled_pages_path(indexed: "no", page: 2)

      patch mark_indexed_crawled_page_path(not_indexed), headers: {"Referer" => "http://www.example.com#{list}"}

      expect(response).to redirect_to("http://www.example.com#{list}")
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq("Marked #{not_indexed.url} as indexed.")
      expect(not_indexed.reload.indexed).to be_truthy
      expect(other.reload.indexed).to be_falsy
    end
  end

  describe "PATCH /crawled_pages/indexed" do
    it "offers a checkbox on each row, tied to one form outside the table" do
      not_indexed

      get crawled_pages_path

      page = Nokogiri::HTML5(response.body)
      form = page.at_css("form#bulk-mark-indexed")
      expect(form["action"]).to eq(mark_indexed_crawled_pages_path)
      expect(form.at_css("input[name=_method]")["value"]).to eq("patch")
      expect(form.at_css("button[type=submit]")["disabled"]).not_to be_nil
      checkbox = page.at_css("tbody tr input[type=checkbox][name='ids[]']")
      expect(checkbox["value"]).to eq(not_indexed.id.to_s)
      expect(checkbox["form"]).to eq("bulk-mark-indexed")
      expect(checkbox["aria-label"]).to eq("Select #{not_indexed.url}")
    end

    it "marks just the ticked pages, counting only those that changed" do
      other = CrawledPage.create!(url: "https://example.com/other", last_modified_at: Time.utc(2026, 7, 5))
      skipped = CrawledPage.create!(url: "https://example.com/skipped", last_modified_at: Time.utc(2026, 7, 5))

      patch mark_indexed_crawled_pages_path, params: {ids: [not_indexed.id, other.id, indexed.id].map(&:to_s)}

      expect(response).to redirect_to(crawled_pages_path)
      expect(flash[:notice]).to eq("Marked 2 pages as indexed.")
      expect([not_indexed, other, skipped].map { it.reload.indexed }).to eq([true, true, false])
    end

    it "says so when every ticked page was already indexed" do
      patch mark_indexed_crawled_pages_path, params: {ids: [indexed.id.to_s]}

      expect(flash[:notice]).to eq("Those pages were already indexed.")
    end

    it "marks nothing when no pages are ticked" do
      not_indexed

      patch mark_indexed_crawled_pages_path, params: {ids: [{"$ne" => ""}]}

      expect(flash[:alert]).to eq("Select at least one page to mark as indexed.")
      expect(not_indexed.reload.indexed).to be_falsy
    end
  end

  describe "PATCH /crawled_pages/:id/not-indexed" do
    it "unmarks just that page" do
      patch mark_not_indexed_crawled_page_path(indexed)

      expect(response).to redirect_to(crawled_pages_path)
      expect(flash[:notice]).to eq("Marked #{indexed.url} as not indexed.")
      expect(indexed.reload.indexed).to be_falsy
    end
  end

  describe "PATCH /crawled_pages/not-indexed" do
    it "is a second submit button on the same form, posting to its own action" do
      not_indexed

      get crawled_pages_path

      button = Nokogiri::HTML5(response.body).at_css("form#bulk-mark-indexed button[formaction='#{mark_not_indexed_crawled_pages_path}']")
      expect(button.text.squish).to eq("Mark as not indexed")
      expect(button["disabled"]).not_to be_nil
    end

    it "unmarks just the ticked pages, counting only those that changed" do
      other = CrawledPage.create!(url: "https://example.com/other", indexed: true, last_modified_at: Time.utc(2026, 7, 5))
      skipped = CrawledPage.create!(url: "https://example.com/skipped", indexed: true, last_modified_at: Time.utc(2026, 7, 5))

      patch mark_not_indexed_crawled_pages_path, params: {ids: [indexed.id, other.id, not_indexed.id].map(&:to_s)}

      expect(flash[:notice]).to eq("Marked 2 pages as not indexed.")
      expect([indexed, other, skipped].map { it.reload.indexed }).to eq([false, false, true])
    end

    it "marks nothing when no pages are ticked" do
      patch mark_not_indexed_crawled_pages_path

      expect(flash[:alert]).to eq("Select at least one page to mark as not indexed.")
    end
  end

  describe "sync requests" do
    it "flags a sitemap sync in progress" do
      SyncRequest.create!(kind: "sitemap", status: "running")

      get crawled_pages_path

      expect(Nokogiri::HTML5(response.body).at_css("#last-sync").text).to include("Sync in progress")
    end

    it "resyncs with the sitemap's own job" do
      post resync_sync_request_path(SyncRequest.create!(kind: "sitemap", status: "failed"))

      expect(SyncSitemapJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(trigger: "resync").id.to_s)
    end
  end
end
