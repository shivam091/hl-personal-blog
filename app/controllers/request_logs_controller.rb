# encoding: UTF-8

# Logs are never edited, only removed, to keep noise and storage down.
class RequestLogsController < ApplicationController
  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :uri, label: "URL contains", placeholder: "e.g. /crawled-pages or ?page="),
    Filtering::DateRange.new(:time, field: :created_at, label: "Time"),
    Filtering::Contains.new(:ip, field: :remote_address, label: "IP contains", placeholder: "e.g. 203.0.113."),
    # Not `method`: an input with that name shadows form.method in the DOM.
    Filtering::Select.new(:http_method, field: :request_method, label: "Method", choices: %w[GET POST PATCH PUT DELETE HEAD OPTIONS]),
    Filtering::Contains.new(:user_agent, field: :user_agent, label: "User agent contains", placeholder: "e.g. bot or iPhone")
  ].freeze
  STATUS_TABS = Filtering::Tabs.new(:status, field: :status, label: "Filter by status",
    choices: {
      "2xx" => ["Success", 200..299],
      "3xx" => ["Redirect", 300..399],
      "4xx" => ["Client error", 400..499],
      "5xx" => ["Server error", 500..599]
    })
  SORT_COLUMNS = {
    "created_at" => "desc",
    "elapsed_time" => "desc",
    "status" => "desc",
    "response_size" => "desc",
    "uri" => "asc"
  }.freeze

  def index
    respond_to do |format|
      format.html do
        @clearance = RequestLogClearance.new
        load_list
      end
      format.csv do
        send_csv RequestLog.to_csv(filtered_logs),
          filename: "request-logs-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
    @request_log = RequestLog.find(params[:id])
  end

  def destroy
    request_log = RequestLog.find(params[:id])
    request_log.destroy
    # Back to the list as it was (same search, sort, and page), so deleting
    # several noisy logs in a row doesn't mean re-finding your place each time.
    redirect_back_or_to request_logs_path, notice: "Deleted the log for #{request_log}.", status: :see_other
  end

  def destroy_selected
    ids = selected_ids

    if ids.empty?
      redirect_back_or_to request_logs_path, alert: "Select at least one log to delete.", status: :see_other
    else
      count = RequestLog.where(:_id.in => ids).delete_all
      redirect_back_or_to request_logs_path, notice: "Deleted #{helpers.pluralize(count, "request log")}.", status: :see_other
    end
  end

  def clear
    @clearance = RequestLogClearance.new(clearance_params)

    if @clearance.valid?
      count = @clearance.scope.count
      @clearance.enqueue
      redirect_to request_logs_path,
        notice: "Clearing #{helpers.pluralize(count, @clearance.local_only ? "local request log" : "request log")} " \
          "from #{l(@clearance.from)} to #{l(@clearance.to)} in the background."
    else
      # So the list behind the reopened dialog keeps its place while the
      # dates are fixed.
      load_list
      render :index, status: :unprocessable_content
    end
  end

  private

  def filtered_logs
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS, tabs: STATUS_TABS)
    # _id is the request id, so it's unique and keeps ties stable across pages.
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @sorting.apply(@filtering.apply(RequestLog.all))
  end

  def load_list
    @pagination = Pagination.new(filtered_logs, params)
    @request_logs = @pagination.records
    @tab_counts = @filtering.tab_counts(RequestLog.all)
  end

  def clearance_params
    params.expect(request_log_clearance: %i[from to local_only])
  end
end
