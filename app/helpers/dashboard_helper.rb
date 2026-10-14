# encoding: UTF-8

module DashboardHelper
  Kpi = Struct.new(:metric, :label, :icon, :hint, :lower_is_better, keyword_init: true)

  KPIS = [
    Kpi.new(metric: :views, label: "Views", icon: "eye", hint: "Human page views; bots are counted apart and left out."),
    Kpi.new(metric: :likes, label: "Likes", icon: "heart",
      hint: "Likes given in the period; each IP address can like a page once. Likes from before they were dated fall in no period."),
    Kpi.new(metric: :subscribers, label: "Subscribers", icon: "users", hint: "New newsletter sign-ups in the period."),
    Kpi.new(metric: :messages, label: "Messages", icon: "message-square", hint: "Messages sent through the contact form.")
  ].freeze

  HIGHER_IS_BETTER = Kpi.new(lower_is_better: false)

  # Matched on host because that's all the frontend stores, and on whole
  # labels so t.co doesn't claim microsoft.com.
  REFERRER_GROUPS = {
    "Search" => /(\A|\.)(google|bing|duckduckgo|yahoo|yandex|baidu|ecosia|brave)\./,
    "Social" => /(\A|\.)(linkedin|lnkd|twitter|facebook|instagram|reddit|youtube|threads|mastodon)\.|\A(t\.co|x\.com|news\.ycombinator\.com)\z/,
    "Direct" => /\Adirect\z/,
    "Internal" => /\Ainternal\z/
  }.freeze

  # So the dashboard words each metric exactly as the Search Console report
  # does.
  def google_search_metrics
    Google::SearchConsole::PerformanceController::METRICS
  end

  # A rate on a handful of views is noise, so it's withheld rather than
  # shown as a confident percentage.
  def rate_or_dash(rate)
    rate ? number_to_percentage(rate * 100, precision: 1) : tag.span("—", class: "text-slate-400", title: "Too few views for a meaningful rate")
  end

  def lifetime_totals(page_views, field)
    page_views.each_with_object(Hash.new(0)) do |page_view, totals|
      page_view.public_send(field).each { |key, count| totals[key] += count.to_i }
    end
  end

  def referrer_groups(referrers)
    referrers.each_with_object(Hash.new(0)) do |(key, count), groups|
      host = referrer_host(key)
      groups[REFERRER_GROUPS.find { |_, pattern| host.match?(pattern) }&.first || "Other sites"] += count
    end
  end

  # The frontend swaps dots for underscores, since MongoDB reads a dot in a
  # key as a path; hostnames have no underscores, so swapping back is safe.
  def referrer_host(key)
    key.to_s.tr("_", ".")
  end

  # Direct and Internal are markers rather than hosts, so they're named like
  # the referrer groups.
  def referrer_label(key)
    host = referrer_host(key)
    host.include?(".") ? host : host.capitalize
  end

  def referrer_hosts(referrers)
    referrers.each_with_object(Hash.new(0)) { |(key, count), hosts| hosts[referrer_host(key)] += count }
  end

  # Under the week each day falls in, Monday first as weekly counts are.
  def weekly_events(events)
    events.each_with_object({}) { |(date, names), weeks| (weeks[date.beginning_of_week] ||= []).concat(names) }
  end

  def country_counts(counts)
    counts.transform_keys { |code| country_label(code) }
  end

  # Only when the period reaches back before the first counted day, since an
  # empty stretch there reads as no traffic rather than no tracking.
  def counted_since_note(period, views:, likes: nil)
    gaps = {"views" => views, "likes" => likes}.select { |_, since| since && period.from < since }
    return if gaps.empty?

    (name, since), (other, other_since) = gaps.to_a
    note = "Page #{name} are counted from #{l(since)}"
    note += " and #{other} from #{l(other_since)}" if other
    "#{note}, so earlier days in this period have none."
  end

  # Only compared once both periods are fully covered by markers, so a rise
  # isn't just the markers reaching further back.
  def visitors_change(stats)
    since = stats.visitors_counted_since
    return tag.span("Not counted yet", class: "text-slate-400") unless since
    return tag.span("Counted from #{l(since)}", class: "text-amber-700") unless stats.visitors_complete?

    previous = stats.period.previous
    metric_change(stats.unique_visitors, (stats.unique_visitors(previous) if stats.visitors_complete?(previous)), HIGHER_IS_BETTER)
  end

  # Lower is better for a position, so a falling number shows as a gain.
  def position_change(current, previous)
    return tag.span("New", class: "text-xs font-medium text-slate-500") if previous.nil?
    return tag.span("—", class: "text-slate-400") if current.nil? || (current - previous).abs < 0.05

    better = current < previous
    tag.span(class: ["inline-flex items-center gap-0.5 font-medium tabular-nums", better ? "text-emerald-700" : "text-red-700"],
      title: "Was #{number_with_precision(previous, precision: 1)}") do
      safe_join([icon(better ? "arrow-up" : "arrow-down", size: 12), number_with_precision((current - previous).abs, precision: 1)])
    end
  end

  def growth_label(growth)
    return tag.span("New", class: "font-medium text-emerald-700") if growth.nil?

    tag.span(class: ["inline-flex items-center gap-0.5 font-medium tabular-nums", growth.negative? ? "text-red-700" : "text-emerald-700"]) do
      safe_join([icon(growth.negative? ? "arrow-down" : "arrow-up", size: 12), number_to_percentage(growth.abs * 100, precision: 0)])
    end
  end
end
