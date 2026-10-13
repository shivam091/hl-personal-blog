# encoding: UTF-8

module RequestLogsHelper
  STATUS_BADGE_CLASSES = {
    2 => "bg-emerald-100 text-emerald-800",
    3 => "bg-sky-100 text-sky-800",
    4 => "bg-amber-100 text-amber-800",
    5 => "bg-red-100 text-red-800"
  }.freeze

  def status_badge(status)
    tag.span(status || "—", class: ["rounded-full px-2 py-0.5 text-xs font-medium tabular-nums",
      STATUS_BADGE_CLASSES.fetch(status.to_i / 100, "bg-slate-100 text-slate-600")])
  end

  def http_method_badge(request_method)
    tag.span(request_method, class: "inline-block w-16 font-mono text-xs font-semibold text-slate-600")
  end

  def duration(log)
    ms = log.elapsed_ms
    ms >= 1000 ? "#{number_with_precision(ms / 1000, precision: 2)} s" : "#{number_with_precision(ms, precision: 1)} ms"
  end

  def duration_class(log)
    if log.elapsed_ms >= 1000 then "text-red-700 font-medium"
    elsif log.elapsed_ms >= 300 then "text-amber-700"
    else "text-slate-600"
    end
  end

  # Lookups vary in detail by IP, so whatever location parts exist are shown.
  def ip_location(ip_info)
    return if ip_info.blank? || ip_info["error"]

    [ip_info["city"], ip_info["region"], ip_info["country"]].compact_blank.uniq.join(", ").presence
  end

  def request_log_stats(log)
    [
      ["Duration", duration(log), duration_class(log), "clock", "From the request reaching the app until its response was fully sent."],
      ["Response size", log.response_size ? number_to_human_size(log.response_size) : "—", "text-slate-900", "file", "The size of the response body the app sent back."],
      ["CPU", number_to_percentage(log.cpu_usage, precision: 1), "text-slate-900", "cpu", "The share of the duration this request spent on the CPU. Low on a slow request means it was waiting on the database or network."],
      # RSS is recorded in kilobytes, as /proc and ps report it.
      ["Memory (RSS)", number_to_human_size(log.memory_usage.to_i * 1024), "text-slate-900", "database", "Memory the whole server process held once the request finished, not just this request's share."]
    ]
  end

  def request_log_request_rows(log)
    [
      ["URL", log.uri],
      ["Method", log.request_method],
      ["User", log.user],
      ["Referrer", log.referrer],
      ["Origin", log.origin],
      ["User agent", log.user_agent],
      ["Session ID", log.session_id],
      ["Session private ID", log.session_private_id]
    ]
  end

  # Named rows rather than the raw lookup, so the facts that matter come
  # first whichever ipinfo endpoints supplied them.
  def request_log_client_rows(log)
    info = log.ip_info || {}
    rows = [
      ["IP address", log.remote_address],
      ["Hostname", info["hostname"]],
      ["Location", ip_location(info)],
      ["Postal code", info["postal"]],
      ["Continent", info["continent"]],
      ["Coordinates", coordinates_link(info["loc"])],
      ["Time zone", info["timezone"]],
      ["Organization", info["org"]],
      ["ASN", [info["asn"], info["as_name"], info["as_domain"]].compact_blank.join(" · ").presence],
      ["Anycast", info.key?("anycast") ? (info["anycast"] ? "Yes" : "No") : nil]
    ]
    rows << ["Lookup error", info["error"]] if info["error"]
    rows
  end

  def coordinates_link(loc)
    latitude, longitude = loc.to_s.split(",")
    return if longitude.blank?

    link_to "https://www.openstreetmap.org/?mlat=#{latitude}&mlon=#{longitude}#map=10/#{latitude}/#{longitude}",
      target: "_blank", rel: "noopener", class: "inline-flex items-center gap-1 underline hover:text-slate-600" do
      safe_join([icon("map-pin", size: 14), loc, icon("external-link", size: 12, class: "text-slate-400")])
    end
  end
end
