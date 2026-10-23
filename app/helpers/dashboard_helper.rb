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

  # So the search charts outside the report mark the same days as unsettled.
  def search_unsettled_from
    return @search_unsettled_from if defined?(@search_unsettled_from)

    @search_unsettled_from = Google::SearchConsole::FinalDate.first_incomplete_date
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

  # Only when the figures reach back before the fix, since a share of
  # Internal from then says nothing about where readers came from.
  def referrers_fixed_note(from)
    fixed = PageView::REFERRERS_FIXED_ON
    "Before #{l(fixed)} every view's referrer was counted as Internal, so only views from then say where readers came from." if from < fixed
  end

  # Keys cut short or written oddly can decode to the same parts, so their
  # counts are added rather than one hiding the other.
  def campaign_counts(campaigns)
    campaigns.each_with_object(Hash.new(0)) { |(key, count), totals| totals[PageView.campaign(key)] += count.to_i }
      .sort_by { |campaign, count| [-count, campaign.to_a] }
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

  # Worded as the views and likes note is, so every figure that began on a
  # later day than the rest says so the same way, and only when the period
  # reaches back before it, for the same reason.
  def counted_from_note(from, counted)
    return unless counted && from < counted.date

    "#{counted.what} are counted from #{l(counted.date)}#{", #{counted.why}" if counted.why}, so earlier days in this period have none."
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

  # Worded as Search Console's Insights words it: the share it moved by, or
  # the clicks before when there were none to take a share of. Nil when the
  # period before wasn't synced.
  def click_change(clicks, previous)
    return if previous.nil?
    return tag.span("—", class: "text-slate-400", title: "No change from the period before") if clicks == previous

    up = clicks > previous
    text = previous.zero? ? "Previously: 0" : number_to_percentage((clicks - previous).abs * 100.0 / previous, precision: 0)
    tag.span(class: ["inline-flex items-center gap-0.5 text-xs font-medium tabular-nums", up ? "text-emerald-700" : "text-red-700"],
      title: "#{number_with_delimiter(previous)} #{"click".pluralize(previous)} in the period before") do
      safe_join([icon(up ? "arrow-up" : "arrow-down", size: 12), text])
    end
  end

  def growth_label(growth)
    return tag.span("New", class: "font-medium text-emerald-700") if growth.nil?

    tag.span(class: ["inline-flex items-center gap-0.5 font-medium tabular-nums", growth.negative? ? "text-red-700" : "text-emerald-700"]) do
      safe_join([icon(growth.negative? ? "arrow-down" : "arrow-up", size: 12), number_to_percentage(growth.abs * 100, precision: 0)])
    end
  end
end
