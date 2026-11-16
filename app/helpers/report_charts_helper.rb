# encoding: UTF-8

module ReportChartsHelper
  def report_messages_verdict_chart(messages, keys, by_verdict, before, previous)
    # Bars of a different width, as with a longer compared period, wouldn't line up with these.
    before_totals = before.timeline.last.values.transpose.map(&:sum) if before && before.per == messages.per
    stacked_chart(keys, verdict_series(by_verdict),
      label: "Contact messages per #{messages.per}, by your verdict#{", against #{previous}" if before_totals}", y_title: "Messages", per: messages.per,
      previous: (aligned(before_totals, keys.size) if before_totals), previous_name: (previous.to_s if before_totals))
  end

  def report_message_bands_chart(bands)
    stacked_chart(bands.map(&:label), band_series(bands), label: "Contact messages by reCAPTCHA score, split by your verdict",
      y_title: "Messages", x_title: "reCAPTCHA score")
  end

  def report_review_movers_chart(named, keys, top, ticks, title, period)
    dumbbell_chart(named.map { |name, values, _| [name, values] }, keys: keys, top: top, ticks: ticks,
      links: named.to_h { |name, _, path| [name, page_view_path(path, **period.query)] },
      x_title: "Views", y_title: "Page", label: "#{title} pages, views before and now")
  end

  def report_newsletter_stays_chart(stays)
    ranking_chart(stays.reject { |band, count| band == NewsletterAudience::UNKNOWN_STAY && count.zero? }.map { |band, count| [band, count, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: stays.values.sum, x_title: "Readers", y_title: "Stayed", label: "Readers who left in the period by how long they'd been subscribed")
  end

  def report_newsletter_sends_chart(sends, per)
    stacked_chart(sends.map(&:start), [ChartsHelper::Series.new(name: "Delivered", values: sends.map(&:sent), color: ChartsHelper::SHARE_COLORS[2]),
      ChartsHelper::Series.new(name: "Undelivered", values: sends.map(&:undelivered), color: ChartsHelper::SHARE_COLORS[1])],
      y_title: "Emails", label: "New-entry emails per #{per}, delivered and still undelivered", per: per)
  end

  def report_subscriber_growth_chart(weekly_totals)
    line_chart(weekly_totals.keys, [ChartsHelper::Series.new(name: "Subscribers", values: weekly_totals.values)], per: :week,
      y_title: "Subscribers", label: "Subscribers on the list at the end of each week, since the first sign-up")
  end

  def report_page_trend_chart(dates, days, granularity, daily, name, slug, style)
    time_chart(dates.zip(granularity.sums(days, daily)), y_title: name, label: "#{name} of #{slug} per #{granularity.by}", style: style,
      per: granularity.per)
  end

  def report_page_search_chart(days, daily, slug)
    measures_chart days, page_search_measures(daily),
      label: "Clicks, impressions and average position of #{slug} per day, each on its own scale"
  end

  def report_launch_curve_chart(launch_curve, typical, slug)
    line_chart(launch_curve.dates,
      [ChartsHelper::Series.new(name: "This entry", values: launch_curve.views),
        (ChartsHelper::Series.new(name: "Typical entry", values: typical, dashed: true) if typical)].compact,
      y_title: "Views so far", label: "Running total of views of #{slug} over its first #{LaunchCurve::DAYS} days, beside the typical entry's")
  end

  def report_like_rate_chart(like_rates)
    ranking_chart(like_rates.compact.zip([[ChartsHelper::SHARE_SWATCHES[0], ChartsHelper::SHARE_COLORS[0]], [ChartsHelper::SHARE_OTHER_SWATCH, ChartsHelper::SHARE_OTHER_COLOR]]).map { |(name, rate), colors| [name, rate, *colors] },
      total: nil, x_title: "Likes per 100 views", y_title: "All time", label: "Likes per 100 views of this page, beside the site's average")
  end

  def report_requests_status_chart(requests, before, granularity, buckets, status_colors, vs)
    stacked_chart(buckets, requests.daily_by_status.map { |name, values| ChartsHelper::Series.new(name: name, values: granularity.sums(requests.dates, values), color: status_colors[name]) },
      y_title: "Requests", label: "Requests per #{granularity.by}, split by status class", per: granularity.per,
      previous: (aligned(before.daily_by_status.transform_values { |values| granularity.sums(before.dates, values) }.values.transpose.map(&:sum), buckets.size) if before), previous_name: vs)
  end

  def report_requests_timing_chart(requests, before, vs)
    timings = requests.daily_timings
    earlier = before&.daily_timings
    lines = [ChartsHelper::Series.new(name: "Median", values: timings[:median]),
      ChartsHelper::Series.new(name: "95th percentile", values: timings[:p95], dashed: true)]
    if earlier
      lines << ChartsHelper::Series.new(name: "Median, #{vs}", values: aligned(earlier[:median], requests.dates.size), dotted: true, color: ChartsHelper::LINE_COLORS[0], against: lines[0])
      lines << ChartsHelper::Series.new(name: "95th percentile, #{vs}", values: aligned(earlier[:p95], requests.dates.size), dotted: true, color: ChartsHelper::LINE_COLORS[1], against: lines[1])
    end
    line_chart(requests.dates, lines,
      y_title: "Milliseconds", unit: " ms", label: "Median and 95th percentile response time per day")
  end

  def report_requests_memory_chart(requests, before, vs)
    memory = [ChartsHelper::Series.new(name: "Memory", values: requests.daily_memory_mb, color: ChartsHelper::LINE_COLORS[0])]
    memory << ChartsHelper::Series.new(name: "Memory, #{vs}", values: aligned(before.daily_memory_mb, requests.dates.size), dotted: true, color: ChartsHelper::LINE_COLORS[0], against: memory[0]) if before
    line_chart(requests.dates, memory,
      y_title: "MB", unit: " MB", label: "The most memory the server process held on each day")
  end

  def report_requests_cpu_chart(requests, before, vs)
    cpu = [ChartsHelper::Series.new(name: "CPU", values: requests.daily_cpu, color: ChartsHelper::LINE_COLORS[0])]
    cpu << ChartsHelper::Series.new(name: "CPU, #{vs}", values: aligned(before.daily_cpu, requests.dates.size), dotted: true, color: ChartsHelper::LINE_COLORS[0], against: cpu[0]) if before
    line_chart(requests.dates, cpu,
      y_title: "% of time", unit: "%", label: "Average share of each request's time spent on the CPU, per day")
  end

  def report_requests_hour_cell(count, max, row, hour, before, vs)
    heat_cell(count, count, max, class: "min-w-6",
      tip: chart_tip("#{Date::DAYNAMES.rotate[row]}, #{format("%02d:00", hour)}", cell_readings("Requests", count, (before.hours[row][hour] if before), vs.to_s)))
  end

  def report_ai_share_chart(ai, search, dates, shares, earlier, earlier_share)
    share_now = ChartsHelper::Series.new(name: "AI share", values: shares)
    lines = [share_now]
    if earlier_share
      earlier_shares = ai.daily(earlier).zip(search.daily(:impressions, earlier)).map { |shown, seen| (shown.to_f / seen * 100).round(1) if shown && seen.to_i.positive? }
      lines << ChartsHelper::Series.new(name: "AI share, #{earlier}", values: aligned(earlier_shares, dates.size), dotted: true, color: ChartsHelper::LINE_COLORS[0], against: share_now)
    end
    line_chart(dates, lines, y_title: "% of impressions", unit: "%",
      label: "AI Overviews and AI Mode impressions as a share of search impressions per day", unsettled: search_unsettled_from)
  end

  def report_search_clicks_chart(buckets, bucketed, bucket_align, granularity, period, per, compared)
    stacked_chart(buckets, [ChartsHelper::Series.new(name: "Clicks", values: bucketed.(:clicks), color: ChartsHelper::BAR_COLOR)],
      y_title: "Clicks", label: "Search clicks per #{per}", per: granularity.per, unsettled: search_unsettled_from,
      previous: bucket_align.(bucketed.(:clicks, period.previous)), previous_name: compared.to_s)
  end

  def report_search_impressions_chart(buckets, bucketed, bucket_align, granularity, period, per, compared)
    impressions_now = ChartsHelper::Series.new(name: "Impressions", values: bucketed.(:impressions))
    line_chart(buckets, [impressions_now,
      ChartsHelper::Series.new(name: "Impressions, #{compared}", values: bucket_align.(bucketed.(:impressions, period.previous)),
        dotted: true, color: ChartsHelper::LINE_COLORS.first, against: impressions_now)],
      y_title: "Impressions", label: "Search impressions per #{per}", per: granularity.per, unsettled: search_unsettled_from)
  end

  def report_search_impressions_time_chart(buckets, bucketed, granularity, per)
    time_chart(buckets.zip(bucketed.(:impressions)), y_title: "Impressions", label: "Search impressions per #{per}", per: granularity.per, style: :line,
      unsettled: search_unsettled_from)
  end

  def report_search_appearances_chart(buckets, dates, appearances, appearances_before, bucket_align, granularity, period, per, compared)
    stacked_chart buckets, share_series(appearances.transform_values { |values| granularity.sums(dates, values) }) { |appearance| humanize_state(appearance) },
      y_title: "Clicks", label: "Search clicks per #{per} by search appearance", per: granularity.per, unsettled: search_unsettled_from,
      previous: (bucket_align.(appearances_before.map { |values| granularity.sums_for(period.previous, values) }.transpose.map { |parts| parts.compact.sum if parts.any? }) if appearances_before&.any?),
      previous_name: compared.to_s
  end

  def report_search_branded_chart(buckets, dates, daily, granularity, per)
    line_chart(buckets, [ChartsHelper::Series.new(name: "Non-branded", values: granularity.sums(dates, daily[Google::SearchConsole::QueryGroups::NON_BRANDED])),
      ChartsHelper::Series.new(name: "Branded", values: granularity.sums(dates, daily[Google::SearchConsole::QueryGroups::BRANDED]), dashed: true)],
      y_title: "Clicks", label: "Search clicks per #{per} from branded and non-branded queries", per: granularity.per, unsettled: search_unsettled_from)
  end

  def report_search_intent_chart(groups, groups_before, compared)
    ranking_chart(groups.map { |group| [group.name, group.impressions, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: groups.sum(&:impressions), x_title: "Impressions", y_title: "Intent", label: "Search impressions by what the query was after",
      previous: groups_before&.to_h { |group| [group.name, group.impressions] }, previous_name: (compared.to_s if groups_before))
  end

  def report_search_ctr_chart(search, points, colors, shortfall)
    scatter_chart(points.map { |point| ChartsHelper::ScatterPoint.new(x: point.position, y: point.ctr, color: colors[point.below?],
        tip: chart_tip(point.query, [{value: metric_value(point.ctr, :percent), name: "CTR", color: colors[point.below?]},
          {value: metric_value(point.expected, :percent), name: "Usual at this position"},
          {value: metric_value(point.position, :position), name: "Average position"},
          {value: number_with_delimiter(point.impressions), name: "Impressions"}])) },
      curve: search.ctr_curve, x_max: Google::SearchConsole::Summary::CURVE_POSITIONS, x_ticks: [1, 5, 10, 15, 20, 25, 30],
      y_tick: ->(value) { axis_value(value, :percent) }, x_title: "Average position", y_title: "CTR",
      label: "CTR against average position for each query, with the site's usual CTR by position",
      key: [["As usual or better", colors[false]], ["Under #{shortfall} of usual", colors[true]]])
  end

  def report_search_positions_chart(distribution)
    time_chart distribution.map { |bucket, row| [bucket, row[:queries]] }, x_title: "Average position",
      y_title: "Queries", label: "Queries by average position"
  end

  def report_search_crawl_ages_chart(ages)
    ranking_chart(ages.map { |bucket, count| [bucket, count, "bg-slate-600", ChartsHelper::BAR_COLOR] }, total: ages.values.sum,
      x_title: "Pages", y_title: "Last crawled", label: "Inspected pages by how long since Google last crawled them")
  end

  def report_syncs_outcome_chart(syncs, before, outcome_series, vs)
    stacked_chart(syncs.dates, syncs.daily_by_outcome.map { |key, values| ChartsHelper::Series.new(name: outcome_series[key].first, values: values, color: outcome_series[key].last) },
      y_title: "Syncs", label: "Sync requests per day, split by how they ended",
      previous: (aligned(before.daily_totals, syncs.dates.size) if before), previous_name: vs)
  end
end
