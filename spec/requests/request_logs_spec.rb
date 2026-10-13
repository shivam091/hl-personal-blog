# encoding: UTF-8

require "rails_helper"

RSpec.describe "Request logs", type: :request do
  # Signing in is itself logged; start each example from a clean slate.
  before { RequestLog.delete_all }

  def create_log(**attributes)
    RequestLog.create!(uri: "https://admin.example.com/", request_method: "GET", status: 200, **attributes)
  end

  describe "GET /request-logs" do
    it "lists logs, filterable by status class, method, and URL" do
      create_log(uri: "https://admin.example.com/ok-page")
      create_log(uri: "https://admin.example.com/broken-page", status: 500)
      create_log(uri: "https://admin.example.com/session", request_method: "POST", status: 302)

      get request_logs_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("/ok-page", "/broken-page", "/session")

      get request_logs_path(status: "5xx")
      expect(response.body).to include("/broken-page")
      expect(response.body).not_to include("/ok-page")

      get request_logs_path(http_method: "POST")
      expect(response.body).to include("/session")
      expect(response.body).not_to include("/ok-page")

      get request_logs_path(q: "broken")
      expect(response.body).to include("/broken-page")
      expect(response.body).not_to include("/ok-page")
    end

    it "sorts by duration" do
      create_log(uri: "https://admin.example.com/fast", elapsed_time: 0.01)
      create_log(uri: "https://admin.example.com/slow", elapsed_time: 2.5)

      get request_logs_path(sort: "elapsed_time", direction: "desc")

      expect(response.body.index("/slow")).to be < response.body.index("/fast")
    end

    it "paginates on the server" do
      RequestLog.collection.insert_many((1..30).map do |n|
        {_id: "req-#{n}", uri: format("https://admin.example.com/p%02d", n), request_method: "GET", status: 200, created_at: Time.utc(2026, 9, n)}
      end)

      get request_logs_path(page: 2)

      expect(response.body).to include("/p05", "/p01", "26–30")
      expect(response.body).not_to include("/p06")
    end

    it "numbers rows on from the previous page" do
      RequestLog.collection.insert_many((1..30).map do |n|
        {_id: "req-#{n}", uri: "https://admin.example.com/p#{n}", request_method: "GET", status: 200, created_at: Time.utc(2026, 9, n)}
      end)

      get request_logs_path(page: 2)

      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("thead th[aria-label='Row number']").text.strip).to eq("#")
      expect(page.css("tbody tr").map { it.css("td")[1].text.strip }).to eq(%w[26 27 28 29 30])
    end

    it "shows an empty state" do
      get request_logs_path
      expect(response.body).to include("No requests logged yet.")
    end

    it "exports every matching log as CSV" do
      create_log(uri: "https://admin.example.com/broken-page", status: 500)
      create_log(uri: "https://admin.example.com/ok-page")

      get request_logs_path(format: :csv, status: "5xx")

      expect(response.media_type).to eq("text/csv")
      rows = CSV.parse(response.body)
      expect(rows.size).to eq(2)
      expect(rows.second).to include("https://admin.example.com/broken-page")
    end

    it "requires signing in", :signed_out do
      get request_logs_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  describe "GET /request-logs/:id" do
    it "shows the request's details" do
      log = create_log(
        uuid: "req-detail", uri: "https://admin.example.com/crawled-pages?q=css", status: 500, user: "admin",
        remote_address: "8.8.8.8", query_params: {"q" => "css"},
        ip_info: {"city" => "Mountain View", "country" => "United States", "asn" => "AS15169", "loc" => "38.0,-122.1"},
        request_headers: {"User-Agent" => "Mozilla/5.0"}, response_headers: {"content-type" => "text/html"},
        exception: {"class" => "RuntimeError", "message" => "boom", "backtrace" => ["app/x.rb:1"]}
      )

      get request_log_path(log)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("req-detail", "/crawled-pages?q=css", "Mountain View, United States", "AS15169",
        "RuntimeError", "boom", "app/x.rb:1", "Mozilla/5.0", "text/html", "openstreetmap.org")
    end

    it "shows times as day, month, year and IST" do
      log = create_log(created_at: Time.utc(2026, 3, 12, 6, 30))

      get request_log_path(log)

      expect(response.body).to include("12 Mar, 2026 12:00 IST")
    end
  end

  describe "DELETE /request-logs/:id" do
    it "offers an icon-only delete with a confirmation on each row" do
      log = create_log(uuid: "row-log", uri: "https://admin.example.com/noisy")

      get request_logs_path

      form = Nokogiri::HTML5(response.body).at_css("tbody tr form[action='#{request_log_path(log)}']")
      expect(form["data-turbo-confirm"]).to eq("Delete the log for GET /noisy? This can't be undone.")
      expect(form.at_css("input[name=_method]")["value"]).to eq("delete")
      button = form.at_css("button")
      expect(button.text.strip).to be_empty
      expect(button["aria-label"]).to eq("Delete the log for GET /noisy")
    end

    it "deletes just that log and returns to the list as it was" do
      log = create_log(uuid: "doomed", uri: "https://admin.example.com/noisy")
      create_log(uuid: "kept")
      list = request_logs_path(status: "2xx", page: 2)

      delete request_log_path(log), headers: {"Referer" => "http://www.example.com#{list}"}

      expect(response).to redirect_to("http://www.example.com#{list}")
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq("Deleted the log for GET /noisy.")
      expect(RequestLog.where(:_id.in => %w[doomed kept]).pluck(:_id)).to eq(["kept"])
    end

    it "falls back to the list without a referrer" do
      log = create_log(uuid: "doomed")

      delete request_log_path(log)

      expect(response).to redirect_to(request_logs_path)
    end
  end

  describe "DELETE /request-logs/selected" do
    it "offers a checkbox on each row, tied to one delete form outside the table" do
      log = create_log(uuid: "row-log", uri: "https://admin.example.com/noisy")

      get request_logs_path

      page = Nokogiri::HTML5(response.body)
      form = page.at_css("form#bulk-delete")
      expect(form["action"]).to eq(destroy_selected_request_logs_path)
      expect(form.at_css("input[name=_method]")["value"]).to eq("delete")
      expect(form.at_css("button[type=submit]")["disabled"]).not_to be_nil
      checkbox = page.at_css("tbody tr input[type=checkbox][name='ids[]']")
      expect(checkbox["value"]).to eq(log.id)
      expect(checkbox["form"]).to eq("bulk-delete")
      expect(checkbox["aria-label"]).to eq("Select the log for GET /noisy")
      expect(page.at_css("thead input[type=checkbox]")["aria-label"]).to eq("Select all logs on this page")
    end

    it "deletes just the ticked logs and returns to the list as it was" do
      create_log(uuid: "doomed-1")
      create_log(uuid: "doomed-2")
      create_log(uuid: "kept")
      list = request_logs_path(status: "2xx", page: 2)

      delete destroy_selected_request_logs_path, params: {ids: %w[doomed-1 doomed-2]},
        headers: {"Referer" => "http://www.example.com#{list}"}

      expect(response).to redirect_to("http://www.example.com#{list}")
      expect(response).to have_http_status(:see_other)
      expect(flash[:notice]).to eq("Deleted 2 request logs.")
      expect(RequestLog.where(:_id.in => %w[doomed-1 doomed-2 kept]).pluck(:_id)).to eq(["kept"])
    end

    it "deletes nothing when no logs are ticked" do
      create_log(uuid: "kept")

      delete destroy_selected_request_logs_path

      expect(response).to redirect_to(request_logs_path)
      expect(flash[:alert]).to eq("Select at least one log to delete.")
      expect(RequestLog.where(_id: "kept")).to exist
    end

    it "ignores ids that aren't plain strings" do
      create_log(uuid: "kept")

      delete destroy_selected_request_logs_path, params: {ids: [{"$ne" => ""}]}

      expect(RequestLog.where(_id: "kept")).to exist
    end
  end

  it "contains the table's sideways scroll, so it can't widen the page on phones" do
    create_log

    get request_logs_path

    # Positioned, so the table's absolutely positioned screen-reader labels
    # scroll with it instead of stretching the page.
    expect(Nokogiri::HTML5(response.body).at_css("table").parent["class"].split).to include("relative", "overflow-x-auto")
  end

  describe "POST /request-logs/clear" do
    it "enqueues clearing the range and says how many logs it covers" do
      create_log(created_at: Time.find_zone("Asia/Kolkata").local(2026, 10, 1, 12))

      expect do
        post clear_request_logs_path, params: {request_log_clearance: {from: "2026-10-01", to: "2026-10-02"}}
      end.to have_enqueued_job(ClearRequestLogsJob).with("2026-10-01", "2026-10-02", local_only: false)

      expect(response).to redirect_to(request_logs_path)
      expect(flash[:notice]).to eq("Clearing 1 request log from 1 Oct, 2026 to 2 Oct, 2026 in the background.")
    end

    it "clears just local logs when the checkbox is ticked" do
      day = Time.find_zone("Asia/Kolkata").local(2026, 10, 1, 12)
      create_log(created_at: day)
      create_log(created_at: day, uri: "http://localhost:3000/request-logs")

      expect do
        post clear_request_logs_path, params: {request_log_clearance: {from: "2026-10-01", to: "2026-10-02", local_only: "1"}}
      end.to have_enqueued_job(ClearRequestLogsJob).with("2026-10-01", "2026-10-02", local_only: true)

      expect(flash[:notice]).to eq("Clearing 1 local request log from 1 Oct, 2026 to 2 Oct, 2026 in the background.")
    end

    it "reopens the modal with the errors under the dates when the range is invalid" do
      expect do
        post clear_request_logs_path, params: {request_log_clearance: {from: "2026-10-05", to: "2026-10-01"}}
      end.not_to have_enqueued_job

      expect(response).to have_http_status(:unprocessable_content)
      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("[data-controller=modal]")["data-modal-open-value"]).to eq("true")
      dialog = page.at_css("dialog")
      expect(dialog.at_css("[role=alert] h2").text.squish).to eq("1 problem kept these logs from being cleared")
      expect(dialog.at_css("#request_log_clearance_to_error").text.squish).to eq("End date can't be before the start date")
    end

    it "keeps the modal closed on a normal visit" do
      get request_logs_path

      page = Nokogiri::HTML5(response.body)
      expect(page.at_css("[data-controller=modal]")["data-modal-open-value"]).to eq("false")
      checkbox = page.at_css("dialog input[type=checkbox][name='request_log_clearance[local_only]']")
      expect(checkbox["checked"]).to be_nil
      expect(page.at_css("dialog label[for=#{checkbox["id"]}]").text.strip).to eq("Only local request logs")
    end

    it "closes only from its buttons, not Escape or a backdrop click" do
      get request_logs_path

      actions = Nokogiri::HTML5(response.body).at_css("dialog")["data-action"].split
      expect(actions).to contain_exactly("cancel->modal#preventDismiss", "keydown.esc->modal#preventDismiss")
    end
  end

  describe "export requests" do
    it "records each CSV export with its filters" do
      create_log(uri: "https://admin.example.com/broken", status: 500)

      get request_logs_path(format: :csv, status: "5xx", page: 2)

      logs = ExportRequest.find_by(section: "Request logs")
      expect(logs).to have_attributes(trigger: "admin", row_count: 1, path: "/request-logs.csv?page=2&status=5xx")
      expect(logs.filters).to eq("status" => "5xx")
    end
  end
end
