# encoding: UTF-8

require "rails_helper"

RSpec.describe "Sync requests", type: :request do
  let!(:enqueued) { stub_sync_kinds }

  def create_request(**attributes)
    SyncRequest.create!(kind: "posts", trigger: "admin", **attributes)
  end

  def table_rows
    Nokogiri::HTML5(response.body).css("tbody tr").map { it.text.squish }
  end

  describe "GET /sync-requests" do
    it "lists each sync with its section, scope, status and outcome" do
      create_request(
        kind: "pages",
        trigger: "rake",
        status: "partial",
        created_count: 3,
        updated_count: 2,
        unchanged_count: 1,
        error_count: 1,
        error_messages: ["Invalid URL: nope"],
        started_at: Time.utc(2026, 10, 7, 10),
        finished_at: Time.utc(2026, 10, 7, 10, 0, 12)
      )
      create_request(kind: "posts")

      get sync_requests_path

      expect(response).to have_http_status(:ok)
      expect(table_rows.find { it.include?("Blog pages") }).to include("Blog sitemap", "Rake task", "Everything Blog sitemap holds", "With errors", "3 created, 2 updated, 1 unchanged", "1 error", "Invalid URL: nope", "took 12.0 s")
      expect(table_rows.find { it.include?("Blog posts") }).to include("Blog feed", "Queued")
    end

    it "filters by section, status and who started it" do
      create_request(kind: "posts", status: "succeeded")
      create_request(kind: "pages", status: "failed", trigger: "rake")

      get sync_requests_path(section: "pages")
      expect(table_rows.join).to include("Blog pages")
      expect(table_rows.join).not_to include("Blog posts")
      expect(response.body).to include("Section: Blog pages")

      get sync_requests_path(status: "succeeded")
      expect(table_rows.join).to include("Blog posts")
      expect(table_rows.join).not_to include("Blog pages")

      get sync_requests_path(trigger: "rake")
      expect(table_rows.size).to eq(1)
    end

    it "counts in-progress requests under one tab" do
      create_request(status: "queued")
      create_request(status: "running")
      create_request(status: "succeeded")

      get sync_requests_path(status: "in_progress")

      expect(table_rows.size).to eq(2)
      expect(response.body).to match(%r{In progress\s*<span[^>]*>2</span>})
    end

    it "sorts by section" do
      create_request(kind: "pages")
      create_request(kind: "posts")

      get sync_requests_path(sort: "kind", direction: "asc")

      expect(table_rows.map { it[/Blog pages|Blog posts/] }).to eq(["Blog pages", "Blog posts"])
    end

    it "paginates on the server" do
      30.times { |n| create_request(created_at: Time.utc(2026, 9, 1) + n.days) }

      get sync_requests_path(page: 2)
      expect(table_rows.size).to eq(5)

      get sync_requests_path(per_page: 50)
      expect(table_rows.size).to eq(30)
    end

    it "offers no resync while a sync is still running" do
      running = create_request(status: "running")
      done = create_request(status: "failed")

      get sync_requests_path

      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("form[action='#{resync_sync_request_path(running)}']")).to be_nil
      expect(page.at_css("form[action='#{resync_sync_request_path(done)}']")).to be_present
    end

    it "shows an empty state" do
      get sync_requests_path
      expect(response.body).to include("No syncs recorded yet.")
    end
  end

  describe "POST /sync-requests/:id/resync" do
    it "queues the same sync again as a new request" do
      original = create_request(kind: "pages", status: "failed")

      expect { post resync_sync_request_path(original) }.to change(SyncRequest, :count).by(1)

      resync = SyncRequest.find_by(trigger: "resync")
      expect(resync.kind).to eq("pages")
      expect(enqueued).to eq([resync])
      expect(response).to redirect_to(sync_requests_path)
      expect(flash[:notice]).to start_with("Resyncing Blog pages from Blog sitemap")
    end
  end

  describe "DELETE /sync-requests/:id" do
    it "deletes one request" do
      request = create_request

      delete sync_request_path(request)

      expect(SyncRequest.count).to eq(0)
      expect(response).to redirect_to(sync_requests_path)
    end
  end

  describe "DELETE /sync-requests/selected" do
    it "deletes the ticked requests only" do
      ticked = [create_request, create_request]
      kept = create_request

      delete destroy_selected_sync_requests_path, params: {ids: ticked.map { it.id.to_s }}

      expect(SyncRequest.pluck(:_id)).to eq([kept.id])
      expect(flash[:notice]).to eq("Deleted 2 sync requests.")
    end

    it "asks for a selection when nothing is ticked" do
      delete destroy_selected_sync_requests_path

      expect(flash[:alert]).to eq("Select at least one sync request to delete.")
    end
  end
end
