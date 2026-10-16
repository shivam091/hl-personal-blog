# encoding: UTF-8

require "rails_helper"

RSpec.describe "Crawled page actions", type: :request do
  describe "POST /crawled-pages/sync" do
    it "queues a sitemap sync from URL inspection" do
      get google_search_console_url_inspections_path
      expect(response.body).to include("Sync sitemap")

      expect { post sync_crawled_pages_path }.to change(SyncRequest, :count).by(1)
      expect(SyncSitemapJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(kind: "sitemap", trigger: "admin").id.to_s)
      expect(response).to redirect_to(google_search_console_url_inspections_path)
      expect(flash[:notice]).to start_with("Syncing pages from the sitemap in the background.")
    end

    it "flags a sitemap sync in progress on URL inspection" do
      SyncRequest.create!(kind: "sitemap", status: "running")

      get google_search_console_url_inspections_path

      expect(response.body).to include("Sync in progress")
    end

    it "resyncs with the sitemap's own job" do
      post resync_sync_request_path(SyncRequest.create!(kind: "sitemap", status: "failed"))

      expect(SyncSitemapJob).to have_been_enqueued.with(request_id: SyncRequest.find_by(trigger: "resync").id.to_s)
    end
  end

  describe "PATCH /crawled-pages/:id/request-indexing" do
    it "marks a page not yet indexed, without calling Google" do
      crawled = CrawledPage.create!(url: "https://example.com/post", last_modified_at: 1.day.ago)

      patch request_indexing_crawled_page_path(crawled)

      expect(crawled.reload.index_requested_at).to be_within(1.minute).of(Time.current)
      expect(flash[:notice]).to eq("Marked https://example.com/post as requested in Search Console. It's marked indexed once an inspection finds it in Google.")
    end

    it "moves the mark to now when a page is requested again" do
      crawled = CrawledPage.create!(url: "https://example.com/post", last_modified_at: 1.day.ago, index_requested_at: 3.days.ago)

      patch request_indexing_crawled_page_path(crawled)

      expect(crawled.reload.index_requested_at).to be_within(1.minute).of(Time.current)
    end

    it "says so when the page is already indexed" do
      indexed = CrawledPage.create!(url: "https://example.com/old", last_modified_at: 1.day.ago, indexed: true)

      patch request_indexing_crawled_page_path(indexed)

      expect(indexed.reload.index_requested_at).to be_nil
      expect(flash[:notice]).to eq("https://example.com/old is already indexed.")
    end
  end

  describe "POST /crawled-pages/:id/inspect" do
    let(:crawled) { CrawledPage.create!(url: "https://example.com/post", last_modified_at: 1.day.ago) }

    it "inspects the page now and opens Google's verdict" do
      service = instance_double(Google::SearchConsole::UrlInspectionSyncService)
      allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new) { service }
      allow(service).to receive(:inspect_now).with(crawled) do
        Google::SearchConsole::UrlInspection.create!(crawled_page: crawled, verdict: "PASS", inspected_at: Time.current)
        SyncResult.new(1, 0, 0, [])
      end

      post inspect_url_crawled_page_path(crawled)

      expect(response).to redirect_to(google_search_console_url_inspection_path(crawled.reload.url_inspection))
      expect(flash[:notice]).to eq("Inspected https://example.com/post just now.")
    end

    it "says why when Google couldn't be asked" do
      service = instance_double(Google::SearchConsole::UrlInspectionSyncService,
        inspect_now: SyncResult.new(0, 0, 0, ["URL inspection of https://example.com/post: quota exhausted"]))
      allow(Google::SearchConsole::UrlInspectionSyncService).to receive(:new) { service }

      post inspect_url_crawled_page_path(crawled), headers: {"HTTP_REFERER" => google_search_console_url_inspections_url}

      expect(response).to redirect_to(google_search_console_url_inspections_url)
      expect(flash[:alert]).to eq("Couldn't inspect https://example.com/post: URL inspection of https://example.com/post: quota exhausted")
    end
  end

  describe "pages not inspected yet" do
    it "lists them on URL inspection, latest change first, each with an inspect button" do
      older = CrawledPage.create!(url: "https://example.com/older", last_modified_at: 3.days.ago)
      newer = CrawledPage.create!(url: "https://example.com/newer", last_modified_at: 1.day.ago)
      inspected = CrawledPage.create!(url: "https://example.com/inspected", last_modified_at: 1.day.ago)
      Google::SearchConsole::UrlInspection.create!(crawled_page: inspected, verdict: "PASS", inspected_at: Time.current)

      get google_search_console_url_inspections_path

      html = Nokogiri::HTML5(response.body)
      card = html.at_css("section[aria-labelledby=not-inspected]")
      expect(card.css("tbody tr").map { |row| row.at_css("td").text.squish }).to eq(%w[/newer /older])
      expect(card.at_css("form[action='#{inspect_url_crawled_page_path(newer)}']")).to be_present
      expect(card.at_css("form[action='#{inspect_url_crawled_page_path(older)}']")).to be_present
      expect(html.at_css("a[href='#not-inspected']").text).to eq("2 crawled pages not inspected yet.")
    end

    it "leaves the card out when every page has been inspected" do
      inspected = CrawledPage.create!(url: "https://example.com/inspected", last_modified_at: 1.day.ago)
      Google::SearchConsole::UrlInspection.create!(crawled_page: inspected, verdict: "PASS", inspected_at: Time.current)

      get google_search_console_url_inspections_path

      expect(Nokogiri::HTML5(response.body).at_css("section[aria-labelledby=not-inspected]")).to be_nil
    end
  end
end
