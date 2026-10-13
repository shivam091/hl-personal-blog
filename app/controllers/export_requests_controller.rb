# encoding: UTF-8

# So it's on record what data left the admin, when and with which filters,
# and an export can be taken again without rebuilding its search.
class ExportRequestsController < ApplicationController
  TRIGGER_TABS = Filtering::Tabs.new(:trigger,
    field: :trigger,
    label: "Filter by where it was taken",
    choices: ExportRequest::TRIGGERS.to_h { |key, label| [key, [label, key]] }
  )
  # Newest first by default, since recent exports are what's usually checked.
  SORT_COLUMNS = {
    "created_at" => "desc",
    "section" => "asc",
    "row_count" => "desc",
    "byte_size" => "desc",
    "filename" => "asc"
  }.freeze

  def index
    @filtering = Filtering.new(params, fields: search_fields, tabs: TRIGGER_TABS)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @pagination = Pagination.new(@sorting.apply(@filtering.apply(ExportRequest.all)), params)
    @export_requests = @pagination.records
    @tab_counts = @filtering.tab_counts(ExportRequest.all)
  end

  def destroy
    export_request = ExportRequest.find(params[:id])
    export_request.destroy
    # Back to the list as it was, so clearing out several in a row keeps
    # your place.
    redirect_back_or_to export_requests_path,
                        notice: "Deleted the #{export_request} from #{l(export_request.created_at)}.",
                        status: :see_other
  end

  def destroy_selected
    ids = selected_ids

    if ids.empty?
      redirect_back_or_to export_requests_path,
                          alert: "Select at least one export request to delete.",
                          status: :see_other
    else
      count = ExportRequest.where(:_id.in => ids).delete_all
      redirect_back_or_to export_requests_path,
                          notice: "Deleted #{helpers.pluralize(count, "export request")}.",
                          status: :see_other
    end
  end

  private

  # Sections come from what's been exported, so the list never offers one
  # that would match nothing.
  def search_fields
    [
      Filtering::Select.new(:section, field: :section, label: "Section", choices: ExportRequest.distinct(:section).compact.sort),
      Filtering::Contains.new(:q, field: :filename, label: "File name contains", placeholder: "e.g. 2026-10 or daily"),
      Filtering::Contains.new(:filter, field: :path, label: "Filters contain", placeholder: "e.g. status=5xx or css-grid"),
      Filtering::DateRange.new(:exported, field: :created_at, label: "Exported")
    ]
  end
end
