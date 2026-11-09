# encoding: UTF-8

module GoogleReportsHelper
  # Stats from both services mark an unknown country this way, so one check
  # covers both.
  UNKNOWN_COUNTRY = "ZZ"

  VERDICT_BADGE_CLASSES = {
    "PASS" => "bg-emerald-100 text-emerald-800",
    "PARTIAL" => "bg-amber-100 text-amber-800",
    "FAIL" => "bg-red-100 text-red-800",
    "NEUTRAL" => "bg-slate-100 text-slate-700"
  }.freeze
  VERDICT_LABELS = {"PASS" => "Indexed", "PARTIAL" => "Partial", "FAIL" => "Error", "NEUTRAL" => "Excluded"}.freeze
  # The badges' hues at chart strength, swatch and hex alike, so a bar
  # matches the badge of the rows it counts.
  VERDICT_CHART_COLORS = {
    "PASS" => ["bg-[#1baf7a]", "#1baf7a"], "PARTIAL" => ["bg-[#eda100]", "#eda100"],
    "FAIL" => ["bg-[#eb6834]", "#eb6834"], "NEUTRAL" => ["bg-[#a8a7a1]", "#a8a7a1"]
  }.freeze

  SEARCH_CONSOLE_URL = "https://search.google.com/search-console"

  # Search Console's own Generative AI report for the synced property, on
  # the view the upload came from, so a figure can be checked, or a new
  # export taken, where it's made. Nil until a property is configured.
  def search_console_generative_ai_url(search_type)
    site = Rails.application.credentials.dig(:google, :search_console_site).presence
    return unless site

    view = search_type.to_s.start_with?("Discover") ? "discover" : "search-analytics"
    "#{SEARCH_CONSOLE_URL}/performance/#{view}/ai?#{{resource_id: site}.to_query}"
  end

  # Totals answer most questions; the daily rows are there for the ones a
  # spreadsheet answers better.
  def report_exports
    query = [@period, @filtering, @sorting, @event_choice].compact.map(&:query).reduce(:merge)
    [
      ["#{@breakdown.label} totals", url_for(action: :index, format: :csv, **query),
        "One row per #{@breakdown.headings.join(" and ").downcase}, added up over the period, as listed here"],
      ["Daily rows", url_for(action: :index, format: :csv, export: "daily", **query),
        "Every stored row in the period, a day at a time"]
    ]
  end

  # Worded as reCAPTCHA's own docs put them, so a figure means the same here
  # as in Google Cloud.
  def recaptcha_summary_metrics
    low_score = Google::Recaptcha::Stat::LOW_SCORE
    [
      Google::DailyReport::Metric.new(field: :requests, label: "Requests", format: :count, icon: "activity",
        hint: "The number of requests reCAPTCHA scored, for every action on the site."),
      Google::DailyReport::Metric.new(field: :low_score_share, label: "Below #{low_score}", format: :percent,
        icon: "alert-triangle", lower_is_better: true,
        hint: "The share of requests scored below #{low_score}, the threshold Google suggests by default. " \
          "1.0 is very likely a good interaction, 0.0 is very likely a bot."),
      Google::DailyReport::Metric.new(field: :average_score, label: "Average score", format: :score, icon: "shield",
        hint: "The average score of the requests. 1.0 is very likely a good interaction, 0.0 is very likely a bot."),
      Google::DailyReport::Metric.new(field: :failed_challenges, label: "Failed challenges", format: :count, icon: "x", lower_is_better: true,
        hint: "Count of submitted challenge solutions that were incorrect or otherwise deemed suspicious, " \
          "so a subsequent challenge was triggered. Only checkbox keys show challenges.")
    ]
  end

  # Worded as GA describes each figure, so it means the same here as there.
  def stickiness_stats(result)
    dau_per_mau = result.average(:dau_per_mau)
    [
      ["Readers a day", number_with_delimiter(result.average(:daily)&.round), "text-slate-900", "users",
        "Average of each day's active users over the period."],
      ["Readers in the last 7 days", number_with_delimiter(result.latest(:weekly)), "text-slate-900", "calendar",
        "Active users over the 7 days to the period's last day."],
      ["Readers in the last 28 days", number_with_delimiter(result.latest(:monthly)), "text-slate-900", "calendar",
        "Active users over the 28 days to the period's last day."],
      ["DAU / MAU", (number_to_percentage(dau_per_mau * 100, precision: 1) if dau_per_mau), "text-slate-900", "heart",
        "Average share of the last 30 days' readers who read on the day. Higher means more readers come back often."]
    ]
  end

  # Shares as percentages, so a line reads as one; each in its own hue,
  # since three lines are more than two shades can tell apart.
  def stickiness_series(result)
    [[:wau_per_mau, "Week / month"], [:dau_per_wau, "Day / week"], [:dau_per_mau, "Day / month"]].each_with_index.map do |(metric, name), index|
      ChartsHelper::Series.new(name: name, values: result.days.map { |day| day[metric] && (day[metric] * 100).round(1) },
        color: ChartsHelper::SHARE_COLORS[index])
    end
  end

  def page_flow_stats(flow)
    [
      ["Views", number_with_delimiter(flow.views), "text-slate-900", "eye", "Times #{flow.path} was viewed in the period."],
      ["Readers", number_with_delimiter(flow.readers), "text-slate-900", "users", "Active users who viewed #{flow.path}, each counted once."]
    ]
  end

  # Worded as GA's Realtime report describes its cards, so a figure means the
  # same here as there.
  def realtime_stats(snapshot)
    [
      ["Active users", number_with_delimiter(snapshot.active_users), "text-slate-900", "users",
        "The number of distinct users who visited your website in the last 30 minutes."],
      ["Views", number_with_delimiter(snapshot.pages.values.sum), "text-slate-900", "eye",
        "The number of app screens or web pages your users viewed in the last 30 minutes. Repeated views of a single page or screen are counted."],
      ["Event count", number_with_delimiter(snapshot.events.values.sum), "text-slate-900", "zap",
        "The number of times users triggered an event in the last 30 minutes."],
      ["Key events", number_with_delimiter(snapshot.key_events.values.sum), "text-slate-900", "target",
        "The number of times users triggered a key event in the last 30 minutes."],
      ["Pages", number_with_delimiter(snapshot.pages.size), "text-slate-900", "file",
        "Views by page title and screen name: how many different pages active users viewed in the last 30 minutes."],
      ["Countries", number_with_delimiter(snapshot.countries.size), "text-slate-900", "globe",
        "Active users by country: how many different countries users visited from in the last 30 minutes."],
      ["Cities", number_with_delimiter(snapshot.cities.size), "text-slate-900", "map-pin",
        "Active users by city: how many different cities users visited from in the last 30 minutes."],
      ["Devices", number_with_delimiter(snapshot.devices.size), "text-slate-900", "cpu",
        "Active users by device category: how many device categories (desktop, mobile, tablet) users are on in the last 30 minutes."]
    ]
  end

  def metric_value(value, format)
    case format
    when :count then number_with_delimiter(value.to_i)
    when :percent then value ? number_to_percentage(value.to_f * 100, precision: 1) : "—"
    # To two places, as GA writes its rates, so the two read alike.
    when :rate then value ? number_to_percentage(value.to_f * 100, precision: 2, strip_insignificant_zeros: true) : "—"
    when :position then value ? number_with_precision(value, precision: 1) : "—"
    when :score, :ratio then value ? number_with_precision(value, precision: 2) : "—"
    when :duration then engagement_duration(value)
    when :milliseconds then value ? "#{number_with_delimiter(value.round)} ms" : "—"
    end
  end

  # Under its column's name, as in GA, so what a column counts is read
  # where it's sorted.
  def event_select(filter, label)
    id = "event-filter-#{filter.param}"
    tag.div(class: "mt-1") do
      safe_join([
        label_tag(id, "Count #{label.downcase} for", class: "sr-only"),
        picker_select_tag(nil, options_for_select([["All events", ""], *@event_choice.choices.fetch(filter.field)], @event_choice.events[filter.field]),
          id: id, class: "h-7 max-w-40 rounded-md border border-slate-300 bg-white px-2 py-0 text-xs font-normal text-slate-900 shadow-sm " \
            "focus:border-slate-500 focus:ring-1 focus:ring-slate-500 focus:outline-none",
          data: {controller: "chart-granularity", chart_granularity_param_value: filter.param, action: "chart-granularity#change"})
      ])
    end
  end

  # The tab itself first, unsplit, so a split can be undone where it was
  # picked; nil for a tab nothing splits.
  def breakdown_splits
    breakdowns = report_breakdowns
    tab = breakdowns.find { |breakdown| breakdown.key == @breakdown.parent } || @breakdown
    splits = breakdowns.select { |breakdown| breakdown.parent == tab.key }
    [tab, *splits] if splits.any?
  end

  # Under the tab's own column, as GA's secondary dimension is, so a split
  # reads as a narrowing of that tab rather than a tab of its own.
  def split_select(splits)
    options = splits.map { |breakdown| [breakdown.split_label || "No split", url_for(action: :index, breakdown: breakdown.key, **breakdown_query)] }
    current = options[splits.index(@breakdown)].last
    tag.div(class: "mt-1") do
      safe_join([
        label_tag("breakdown-split", "Split #{splits.first.label.downcase} by", class: "sr-only"),
        picker_select_tag(nil, options_for_select(options, current),
          id: "breakdown-split", class: "h-7 max-w-48 rounded-md border border-slate-300 bg-white px-2 py-0 text-xs font-normal text-slate-900 shadow-sm " \
            "focus:border-slate-500 focus:ring-1 focus:ring-slate-500 focus:outline-none",
          data: {controller: "visit-select", action: "visit-select#change"})
      ])
    end
  end

  # Rates and averages are dashed and counts solid, so a count is told from
  # a rate by more than colour. The period compared with is dotted.
  def trend_measures(trend, metrics)
    metrics.select { |metric| trend.selection.fields.include?(metric.field) }.map do |metric|
      ChartsHelper::Measure.new(name: metric.label, values: trend.values.fetch(metric.field), color: metric.color,
        dashed: metric.format != :count, inverted: metric.lower_is_better, whole: metric.format == :count,
        tick: ->(value) { axis_value(value, metric.format) }, reading: ->(value) { metric_value(value, metric.format) },
        previous: trend.previous&.fetch(metric.field), previous_name: ("#{metric.label}, #{@period.previous}" if trend.previous))
    end
  end

  # In Search Console's colours and on its scales, so a page's chart reads
  # like the site's.
  def page_search_measures(daily)
    google_search_metrics.select { |metric| daily.key?(metric.field) }.map do |metric|
      ChartsHelper::Measure.new(
        name: metric.label,
        values: daily.fetch(metric.field),
        color: metric.color,
        dashed: metric.format != :count,
        inverted: metric.lower_is_better,
        whole: metric.format == :count,
        tick: ->(value) { axis_value(value, metric.format) },
        reading: ->(value) { metric_value(value, metric.format) }
      )
    end
  end

  # Shorter than a figure in full, since an axis label has a narrow column.
  def axis_value(value, format)
    case format
    when :count then compact_number(value)
    when :percent, :rate then number_to_percentage(value * 100, precision: 2, strip_insignificant_zeros: true)
    else number_with_precision(value, precision: 1, strip_insignificant_zeros: true)
    end
  end

  # Written as GA writes a share, so the two read alike.
  def share_of_total(value, total)
    return if total.to_f.zero?

    number_to_percentage(value.to_f / total * 100, precision: 2, strip_insignificant_zeros: true)
  end

  # Decided in one place, so a column shows a change or a share, never both;
  # a picked comparison is what the whole table is read against, as in GA.
  # A size smaller than the figure, so the figure is what's read first.
  def report_cell_aside(row, metric)
    value = row.value(metric.field)
    if comparing? && @previous_rows
      row_change(value, @previous_rows[@breakdown.keys.map { |key| row[key] }]&.value(metric.field), metric)
    elsif metric.row_change
      nil
    elsif report_shares? && metric.format == :count
      share = share_of_total(value, @totals.value(metric.field))
      tag.span("(#{share})", class: "block text-xs text-slate-500") if share
    end
  end

  # A day's figures as the summary tiles name them, so a row's change is
  # worked out and coloured as the tile's is; nil where a day has no
  # requests to divide by, or no challenges reported.
  def recaptcha_day_figures(stat)
    {
      requests: stat.requests,
      low_score_share: (stat.low_score_requests.fdiv(stat.requests) if stat.requests.positive?),
      average_score: stat.average_score,
      failed_challenges: (stat.challenges["failed"].to_i if stat.challenges.key?("failed"))
    }
  end

  # Beside a cell's figure, so a row can be judged against itself; a row
  # with nothing before has no rate of change, only a start. Under the
  # figure, as in Search Console, so a column's figures stay aligned
  # whatever sits beside them. Forced for a table that exists to show change,
  # so it isn't left with only the figures when comparison is switched off.
  def row_change(current, previous, metric, stacked: true, force: false)
    return unless force || comparing?

    label = CompareChange.label(current, previous)
    before = @period&.compare_countries? ? country_label(@period.compare_country) : "the period before"
    block = "block " if stacked
    case label
    when CompareChange::NONE_IN_EITHER then return tag.span(label, class: "#{block}text-xs text-slate-400", title: "None in either period")
    when CompareChange::NEW then return tag.span(label, class: "#{block}text-xs text-emerald-700", title: "None in #{before}")
    when CompareChange::UNCHANGED then return tag.span(label, class: "#{block}text-xs text-slate-500", title: "No change from #{before}")
    end

    current = current.to_f
    previous = previous.to_f
    change = current - previous
    better = metric.lower_is_better ? change.negative? : change.positive?
    tag.span(label, class: [(stacked ? "block text-xs" : "text-xs"), better ? "text-emerald-700" : "text-red-700"],
      title: "#{change.positive? ? "Up" : "Down"} from #{metric.try(:format) ? metric_value(previous, metric.format) : number_with_delimiter(previous.round)} in #{before}")
  end

  # Minutes and seconds read faster than a count of seconds.
  def engagement_duration(seconds)
    seconds = seconds.to_f.round
    seconds >= 60 ? "#{seconds / 60}m #{format("%02d", seconds % 60)}s" : "#{seconds}s"
  end

  # Changes only show once a comparison is picked, as in Search Console, so
  # every badge on a page answers the same question.
  def comparing?
    @period&.compare?
  end

  # Coloured by whether the change is good rather than by its sign, since a
  # lower search position is a better one.
  def metric_change(current, previous, metric)
    return unless comparing?
    if @period.compare_countries? && (current.nil? || previous.nil? || previous.zero?)
      return tag.span("—", class: "text-slate-400", title: "Not split by country, or none in #{country_label(@period.compare_country)}")
    end
    return tag.span("No earlier data", class: "text-slate-400") if current.nil? || previous.nil? || previous.zero?

    change = (current.to_f - previous) / previous
    return tag.span("No change", class: "text-slate-500") if change.abs < 0.0005

    better = metric.lower_is_better ? change.negative? : change.positive?
    tag.span(class: ["inline-flex items-center gap-0.5 font-medium tabular-nums", better ? "text-emerald-700" : "text-red-700"]) do
      safe_join([icon(change.positive? ? "arrow-up" : "arrow-down", size: 12), number_to_percentage(change.abs * 100, precision: 1)])
    end
  end

  # As in Search Console, a value narrows the whole report to itself, so a
  # day's or a query's pages, countries and devices are one tab away.
  def breakdown_value(row, key)
    value = row.value(key)
    if key == :date
      return link_to(url_for(action: :index, **breakdown_query, from: value.iso8601, to: value.iso8601),
        title: "Show #{l(value)} only", class: "font-medium text-slate-900 hover:underline") { tag.time(l(value), datetime: value.iso8601) }
    end

    shown = key == :country ? country_label(value) : Google::DailyReport.value_label(key, value.presence)
    return tag.span("—", class: "text-slate-400") unless shown

    # As in GA, an event opens a page of its own rather than narrowing the
    # list to itself.
    if key == :event_name
      return link_to(shown, google_analytics_event_path(value, **@period.query), title: "Open #{shown}",
        class: "font-medium text-slate-900 hover:underline")
    end

    filter = breakdown_filter(key, value)
    return shown unless filter

    link_to shown, url_for(action: :index, **breakdown_query, **filter), title: "Show #{shown} only", class: "text-slate-900 hover:underline"
  end

  # A page is searched by its path, since that's how every report names it.
  def breakdown_filter(key, value)
    return if value.blank?

    field_name, value = key == :page ? [:page_path, url_path(value)] : [key, value]
    field = @filtering.fields.find { |candidate| candidate.field == field_name && candidate.respond_to?(:exact_query) }
    field.exact_query(value) if field && value
  end

  # Beside the row, as in Search Console, so a page can be checked live or
  # in Google's index without leaving the report.
  def breakdown_actions(row, key)
    value = row.value(key)
    return if value.blank?

    case key
    when :page
      return unless (live_url = http_url(value))

      safe_join([
        copy_button(value, "Copy URL to clipboard"),
        row_action(live_url, "Open in new tab", "external-link", external: true),
        inspect_action(value),
        request_indexing_action(value)
      ].compact)
    when :page_path
      return unless (live_url = blog_live_url(value))

      safe_join([
        copy_button(live_url, "Copy URL to clipboard"),
        row_action(live_url, "Open in new tab", "external-link", external: true)
      ])
    when :query
      safe_join([
        copy_button(value, "Copy query to clipboard"),
        row_action("https://www.google.com/search?#{{q: value}.to_query}", "Search Google for it", "search", external: true)
      ])
    end
  end

  # Prefers the verdict already held, so opening it spends none of the day's
  # inspection quota. Only crawled pages, since that's what an inspection is
  # kept against.
  def inspect_action(url)
    known = @inspections&.[](url)
    if known&.[](:inspection)
      row_action(google_search_console_url_inspection_path(known[:inspection]), "Inspect URL", "file-search")
    elsif known
      button_to inspect_url_crawled_page_path(known[:page]), form_class: "inline-flex", class: ROW_ACTION_CLASS, aria: {label: "Inspect URL"} do
        icon("file-search", size: 15)
      end
    end
  end

  def request_indexing_action(url)
    known = @inspections&.[](url)
    return if known.nil? || known[:indexed]

    button_to request_indexing_crawled_page_path(known[:page]), method: :patch, form_class: "inline-flex", class: ROW_ACTION_CLASS,
      aria: {label: "Mark as requested"} do
      icon("clock", size: 15)
    end
  end

  def url_path(url)
    URI.parse(url).path.presence || "/"
  rescue URI::InvalidURIError
    nil
  end

  # Named by a tooltip drawn from the label, so the name a screen reader
  # hears and the one shown can't drift apart.
  ROW_ACTION_CLASS = "relative inline-flex size-7 items-center justify-center rounded-full text-slate-500 hover:bg-slate-200 hover:text-slate-900 " \
    "focus-visible:outline-2 focus-visible:outline-slate-500 after:pointer-events-none after:absolute after:bottom-full after:left-1/2 after:z-20 " \
    "after:mb-1 after:-translate-x-1/2 after:rounded after:bg-slate-800 after:px-2 after:py-1 after:text-xs after:whitespace-nowrap after:text-white " \
    "after:opacity-0 after:content-[attr(aria-label)] hover:after:opacity-100 focus-visible:after:opacity-100"

  def copy_button(text, label)
    tag.button(icon("copy", size: 15), type: "button", class: ROW_ACTION_CLASS, aria: {label: label},
      data: {controller: "clipboard", clipboard_text_value: text, action: "clipboard#copy"})
  end

  def row_action(url, label, icon_name, external: false)
    link_to icon(icon_name, size: 15), url, class: ROW_ACTION_CLASS, aria: {label: label}, **(external ? {target: "_blank", rel: "noopener"} : {})
  end

  # A flag is quicker to recognise than a two-letter code.
  def country_label(code)
    return "Unknown" if code.blank? || code == UNKNOWN_COUNTRY

    "#{country_flag(code)} #{code}"
  end

  # The offset from "A" to the regional indicator letters, which pair up
  # into a flag emoji.
  def country_flag(code)
    code.to_s.upcase.chars.map { |char| (char.ord + 127_397).chr(Encoding::UTF_8) }.join
  end

  # Labelled as Search Console labels them, so a badge means what it does
  # there.
  def verdict_chart_color(verdict)
    VERDICT_CHART_COLORS.fetch(verdict, [ChartsHelper::SHARE_OTHER_SWATCH, ChartsHelper::SHARE_OTHER_COLOR])
  end

  def verdict_label(verdict)
    VERDICT_LABELS.fetch(verdict, verdict.presence || "—")
  end

  def verdict_badge(verdict)
    tag.span(verdict_label(verdict),
      class: ["rounded-full px-2 py-0.5 text-xs font-medium whitespace-nowrap", VERDICT_BADGE_CLASSES.fetch(verdict, "bg-slate-100 text-slate-600")])
  end

  # Search Console's SCREAMING_SNAKE_CASE enums are slow to scan.
  def humanize_state(state)
    state.present? ? state.to_s.downcase.humanize : "—"
  end

  def yes_no(value)
    value ? "Yes" : "No"
  end

  def assessment_outcome_badge(assessment)
    if assessment.accepted
      tag.span("Accepted", class: "rounded-full bg-emerald-100 px-2 py-0.5 text-xs font-medium text-emerald-800")
    else
      tag.span("Rejected", class: "rounded-full bg-red-100 px-2 py-0.5 text-xs font-medium text-red-800")
    end
  end

  def url_inspection_rows(inspection)
    [
      ["Verdict", verdict_badge(inspection.verdict)],
      ["Coverage", inspection.coverage_state],
      ["Indexing allowed", humanize_state(inspection.indexing_state)],
      ["Robots.txt", humanize_state(inspection.robots_txt_state)],
      ["Page fetch", humanize_state(inspection.page_fetch_state)],
      ["Crawled as", humanize_state(inspection.crawled_as)],
      ["Last crawled", time_or_dash(inspection.last_crawled_at)],
      ["First indexed", first_indexed_detail(inspection)],
      ["Inspected", time_or_dash(inspection.inspected_at)]
    ]
  end

  # Shown with the check before it, since Google doesn't say when it got in.
  def first_indexed_detail(inspection)
    return time_or_dash(nil) unless inspection.first_indexed_at

    detail = inspection.indexed_after ? safe_join([" (not indexed at ", time_tag(inspection.indexed_after), ")"]) : " (indexed when first inspected)"
    safe_join([time_tag(inspection.first_indexed_at), tag.span(detail, class: "text-slate-500")])
  end

  def url_inspection_canonical_rows(inspection)
    [
      ["Declared canonical", inspection.user_canonical],
      ["Google's canonical", inspection.google_canonical],
      ["Match", inspection.canonical_mismatch? ? tag.span("Google chose a different URL", class: "font-medium text-amber-700") : "Yes"]
    ]
  end

  def assessment_rows(assessment)
    [
      ["Outcome", assessment_outcome_badge(assessment)],
      ["Score", recaptcha_score_badge(assessment.score)],
      ["Action", assessment.action],
      ["Expected action", assessment.expected_action],
      ["Valid token", yes_no(assessment.valid_token)],
      ["Invalid reason", assessment.invalid_reason],
      ["Reasons", assessment.reasons.join(", ").presence],
      ["Password", humanize_state(assessment.password_outcome)],
      ["Feedback sent to Google", time_or_dash(assessment.annotated_at)],
      ["Time", time_or_dash(assessment.created_at)]
    ]
  end

  def assessment_client_rows(assessment)
    [
      ["IP address", assessment.remote_ip],
      ["User agent", assessment.user_agent],
      ["Hostname", assessment.hostname],
      ["Token created", time_or_dash(assessment.token_created_at)],
      ["Enterprise assessment", assessment.name]
    ]
  end
end
