# encoding: UTF-8

class ExternalCallsController < ApplicationController
  STATUS_TABS = Filtering::Tabs.new(:status, field: :status, label: "Filter by status",
    choices: {
      "2xx" => ["Success", 200..399],
      "4xx" => ["Refused", 400..499],
      "5xx" => ["Server error", 500..599],
      "none" => ["No response", nil]
    })
  SORT_COLUMNS = {"created_at" => "desc", "duration_ms" => "desc", "status" => "desc", "service" => "asc"}.freeze

  def index
    @filtering = Filtering.new(params, fields: search_fields, tabs: STATUS_TABS)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @pagination = Pagination.new(@sorting.apply(@filtering.apply(ExternalCall.all)), params)
    @external_calls = @pagination.records
    @tab_counts = @filtering.tab_counts(ExternalCall.all)
  end

  def destroy
    external_call = ExternalCall.find(params[:id])
    external_call.destroy
    redirect_back_or_to external_calls_path, notice: "Deleted the #{external_call} call from #{l(external_call.created_at)}.", status: :see_other
  end

  def destroy_selected
    ids = selected_ids

    if ids.empty?
      redirect_back_or_to external_calls_path, alert: "Select at least one call to delete.", status: :see_other
    else
      count = ExternalCall.where(:_id.in => ids).delete_all
      redirect_back_or_to external_calls_path, notice: "Deleted #{helpers.pluralize(count, "external call")}.", status: :see_other
    end
  end

  private

  # Built per request, so a service first called after boot is offered.
  def search_fields
    [
      Filtering::Select.new(:service, field: :service, label: "Service", choices: ExternalCall.services.index_by(&:itself)),
      Filtering::DateRange.new(:time, field: :created_at, label: "Time"),
      Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. searchAnalytics or feed.xml"),
      Filtering::Contains.new(:error, field: :error, label: "Error contains", placeholder: "e.g. timeout or 403")
    ]
  end
end
