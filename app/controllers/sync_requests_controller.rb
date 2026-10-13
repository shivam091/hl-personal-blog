# encoding: UTF-8

# So a sync that failed, was skipped or never ran is noticed and can be run
# again.
class SyncRequestsController < ApplicationController
  # A stalled request is still stored as queued or running, so it shows
  # under In progress, flagged.
  STATUS_TABS = Filtering::Tabs.new(:status, field: :status, label: "Filter by status",
    choices: {
      "in_progress" => ["In progress", {"$in" => SyncRequest::IN_PROGRESS}],
      "succeeded" => ["Succeeded", "succeeded"],
      "partial" => ["With errors", "partial"],
      "failed" => ["Failed", "failed"]
    })
  # Newest first by default, since the latest syncs are what's usually checked.
  SORT_COLUMNS = {
    "created_at" => "desc",
    "finished_at" => "desc",
    "kind" => "asc",
    "status" => "asc"
  }.freeze

  def index
    @filtering = Filtering.new(params, fields: search_fields, tabs: STATUS_TABS)
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @pagination = Pagination.new(@sorting.apply(@filtering.apply(SyncRequest.all)), params)
    @sync_requests = @pagination.records
    @tab_counts = @filtering.tab_counts(SyncRequest.all)
  end

  def resync
    sync_request = SyncRequest.find(params[:id])
    sync_request.resync
    redirect_back_or_to sync_requests_path,
                        notice: "Resyncing #{sync_request.section} from #{sync_request.source} in the background. Refresh in a moment to see how it went.",
                        status: :see_other
  end

  def destroy
    sync_request = SyncRequest.find(params[:id])
    sync_request.destroy
    # Back to the list as it was, so clearing out several in a row keeps your place.
    redirect_back_or_to sync_requests_path,
                        notice: "Deleted the #{sync_request} from #{l(sync_request.created_at)}.",
                        status: :see_other
  end

  def destroy_selected
    ids = selected_ids

    if ids.empty?
      redirect_back_or_to sync_requests_path,
                          alert: "Select at least one sync request to delete.",
                          status: :see_other
    else
      count = SyncRequest.where(:_id.in => ids).delete_all
      redirect_back_or_to sync_requests_path,
                          notice: "Deleted #{helpers.pluralize(count, "sync request")}.",
                          status: :see_other
    end
  end

  private

  # Built per request, so kinds added after boot are offered.
  def search_fields
    [
      Filtering::Select.new(:section, field: :kind, label: "Section", choices: SyncRequest::KINDS.transform_values(&:section)),
      Filtering::Select.new(:trigger, field: :trigger, label: "Started by", choices: SyncRequest::TRIGGERS),
      Filtering::DateRange.new(:requested, field: :created_at, label: "Requested"),
      Filtering::Contains.new(:error, field: :error_messages, label: "Error contains", placeholder: "e.g. quota or credentials")
    ]
  end
end
