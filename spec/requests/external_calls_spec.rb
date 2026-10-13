# encoding: UTF-8

require "rails_helper"

RSpec.describe "External calls", type: :request do
  def create_call(**attributes)
    ExternalCall.create!(service: "Search Console", http_method: "POST", status: 200, duration_ms: 420, response_size: 2048,
      url: "https://searchconsole.googleapis.com/webmasters/v3/sites/x/searchAnalytics/query", **attributes)
  end

  def table_rows
    Nokogiri::HTML5(response.body).css("tbody tr").map { it.text.squish }
  end

  describe "GET /external-calls" do
    it "lists each call with its service, request, status, duration and size" do
      create_call(status: 403, duration_ms: 12_500, error: "the server responded with status 403", error_body: '{"error":"No access"}')

      get external_calls_path

      expect(response).to have_http_status(:ok)
      expect(table_rows.first).to include("Search Console", "POST", "searchAnalytics/query", "403", "12.50 s", "2 KB",
        "the server responded with status 403", "No access")
    end

    it "filters by service and status" do
      create_call
      create_call(service: "Atom feed", http_method: "GET", url: "https://blog.example/feed.xml", status: nil, error: "timeout")

      get external_calls_path(service: "Atom feed")
      expect(table_rows.join).to include("feed.xml")
      expect(table_rows.join).not_to include("searchAnalytics")

      get external_calls_path(status: "none")
      expect(table_rows.size).to eq(1)
      expect(table_rows.first).to include("timeout")
    end
  end

  describe "DELETE /external-calls/selected" do
    it "deletes the chosen calls" do
      keep = create_call
      gone = create_call

      delete destroy_selected_external_calls_path, params: {ids: [gone.id.to_s]}

      expect(ExternalCall.all.to_a).to eq([keep])
    end
  end
end
