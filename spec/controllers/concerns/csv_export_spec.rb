# encoding: UTF-8

require "rails_helper"

RSpec.describe CsvExport, type: :controller do
  controller(ApplicationController) do
    skip_before_action :require_authentication

    def index
      send_csv "URL,Status\nhttps://example.com/a,200\nhttps://example.com/b,500\n",
               filename: "pages.csv",
               detail: "Failing pages"
    end
  end

  it "sends the CSV and records the export with its section, filters and size" do
    routes.draw { get "sync-requests" => "anonymous#index" }

    get :index, params: {status: "failed", page: 2}, format: :csv

    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to include('filename="pages.csv"')
    expect(ExportRequest.first).to have_attributes(
      section: "Sync requests", detail: "Failing pages", filename: "pages.csv",
      row_count: 2, trigger: "admin"
    )
    expect(ExportRequest.first.filters).to eq("status" => "failed")
  end
end
