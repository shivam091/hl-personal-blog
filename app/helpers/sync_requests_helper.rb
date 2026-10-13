# encoding: UTF-8

module SyncRequestsHelper
  SYNC_STATUS_BADGES = {
    "queued" => ["Queued", "bg-slate-100 text-slate-700"],
    "running" => ["Running", "bg-sky-100 text-sky-800"],
    "succeeded" => ["Succeeded", "bg-emerald-100 text-emerald-800"],
    "partial" => ["With errors", "bg-amber-100 text-amber-800"],
    "failed" => ["Failed", "bg-red-100 text-red-800"],
    "stalled" => ["Stalled", "bg-orange-100 text-orange-800"]
  }.freeze

  def sync_status_badge(sync_request)
    label, classes = SYNC_STATUS_BADGES.fetch(sync_request.display_status)
    tag.span(label, class: ["rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap", classes])
  end

  def sync_status_label(status)
    SYNC_STATUS_BADGES.fetch(status).first
  end

  # Said the way the sync was asked for, so a resync's scope is clear
  # before it's clicked.
  def sync_scope(sync_request)
    if sync_request.days
      "#{l(sync_request.from_date)} – #{l(sync_request.to_date)} (#{pluralize(sync_request.days, "day")})"
    elsif sync_request.limit
      "Next #{pluralize(sync_request.limit, "page")}"
    else
      "Everything #{sync_request.source} holds"
    end
  end

  def sync_counts(sync_request)
    {
      created: sync_request.created_count,
      updated: sync_request.updated_count,
      unchanged: sync_request.unchanged_count
    }.map { |label, count| "#{number_with_delimiter(count)} #{label}" }.join(", ")
  end

  def sync_duration(sync_request)
    seconds_label(sync_request.duration)
  end

  def seconds_label(seconds)
    return "—" unless seconds

    if seconds >= 60
      "#{(seconds / 60).floor} min #{(seconds % 60).round} s"
    else
      "#{number_with_precision(seconds, precision: 1)} s"
    end
  end

  # Named when a page shows more than one, so each line says which sync
  # it dates.
  def last_sync_status(kind, label: nil, id: "last-sync")
    render "shared/last_sync", kind: kind, completed: SyncRequest.last_completed(kind),
           latest: SyncRequest.latest(kind), label: label, id: id
  end
end
