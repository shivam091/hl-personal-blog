# encoding: UTF-8

require "rails_helper"

RSpec.describe "Export requests", type: :request do
  def create_request(**attributes)
    ExportRequest.create!(
      section: "Request logs",
      path: "/request-logs.csv",
      filename: "request-logs-2026-10-12.csv",
      row_count: 10,
      byte_size: 2048,
      **attributes
    )
  end

  def table_rows
    Nokogiri::HTML5(response.body).css("tbody tr").map { it.text.squish }
  end

  describe "GET /export-requests" do
    it "lists each export with its section, filters, file and size" do
      create_request(path: "/request-logs.csv?status=5xx&q=post")

      get export_requests_path

      expect(response).to have_http_status(:ok)
      expect(table_rows.first).to include("Request logs", "Admin", "status: 5xx", "q: post", "request-logs-2026-10-12.csv", "10", "2 KB")
      reexport = Nokogiri::HTML5(response.body).at_css("a[title='Re-export']")
      expect(reexport["href"]).to eq("/request-logs.csv?status=5xx&q=post")
    end

    it "filters by section, file name and where it was taken" do
      create_request
      create_request(section: "Crawled pages", path: "/crawled-pages.csv", filename: "crawled.csv", trigger: "rake")

      get export_requests_path(section: "Crawled pages")
      expect(table_rows.join).to include("crawled.csv")
      expect(table_rows.join).not_to include("request-logs-2026-10-12.csv")

      get export_requests_path(q: "request-logs")
      expect(table_rows.size).to eq(1)

      get export_requests_path(trigger: "rake")
      expect(table_rows.join).to include("Rake task")
      expect(table_rows.size).to eq(1)
    end

    it "sorts by rows" do
      create_request(filename: "small.csv", row_count: 1)
      create_request(filename: "big.csv", row_count: 500)

      get export_requests_path(sort: "row_count", direction: "desc")

      expect(response.body.index("big.csv")).to be < response.body.index("small.csv")
    end

    it "paginates on the server" do
      30.times { |n| create_request(created_at: Time.utc(2026, 9, 1) + n.days) }

      get export_requests_path(page: 2)
      expect(table_rows.size).to eq(5)

      get export_requests_path(per_page: 50)
      expect(table_rows.size).to eq(30)
    end

    it "shows an empty state" do
      get export_requests_path
      expect(response.body).to include("No exports recorded yet.")
    end
  end

  describe "DELETE /export-requests/:id" do
    it "deletes one request" do
      request = create_request

      delete export_request_path(request)

      expect(ExportRequest.count).to eq(0)
      expect(response).to redirect_to(export_requests_path)
    end
  end

  describe "DELETE /export-requests/selected" do
    it "deletes the ticked requests only" do
      ticked = [create_request, create_request]
      kept = create_request

      delete destroy_selected_export_requests_path, params: {ids: ticked.map { it.id.to_s }}

      expect(ExportRequest.pluck(:_id)).to eq([kept.id])
      expect(flash[:notice]).to eq("Deleted 2 export requests.")
    end
  end
end
