# encoding: UTF-8

module AnalyticsChartsHelper
  def analytics_reader_interactions_chart(rows, views:, previous:, period:)
    per_hundred = lambda do |event, count|
      rate = tag.span("(#{number_with_precision(count * 100.0 / views, precision: 1)})", class: "text-slate-500", title: "Per 100 views")
      previous ? safe_join([rate, row_change(count, previous.fetch(event, 0), DashboardHelper::HIGHER_IS_BETTER, stacked: false)], " ") : rate
    end
    ranking_chart(rows.map { |_, label, count| [label, count, "bg-slate-600", ChartsHelper::BAR_COLOR] }, total: rows.sum(&:last),
      previous: (rows.to_h { |event, label, _| [label, previous.fetch(event, 0)] } if previous), previous_name: period.previous.to_s,
      links: rows.to_h { |event, label, _| [label, google_analytics_event_path(event, **period.query)] },
      changes: views.positive? ? rows.to_h { |event, label, count| [label, per_hundred.(event, count)] } : {},
      x_title: "Events", y_title: "Interaction", label: "Reader interactions in #{period}, most first")
  end

  def analytics_channel_mix_chart(channel_mix)
    share_chart channel_mix, key_label: ->(channel) { channel.presence || "(not set)" },
      count_name: "session", empty: "No sessions in this period.", y_title: "Share of sessions",
      label: "Each #{channel_mix[:unit]}'s sessions split by channel, as a share of that #{channel_mix[:unit]}"
  end

  def analytics_campaign_chart(campaign_results, period)
    results = lambda do |figures|
      engaged = figures[:sessions].positive? ? number_to_percentage(figures[:engaged_sessions] * 100.0 / figures[:sessions], precision: 0) : "—"
      tag.span("#{engaged} engaged · #{pluralize(figures[:key_events], "key event")}", class: "text-slate-500")
    end
    sessions_total = campaign_results.sum { |_, figures| figures[:sessions] }
    ranking_chart(campaign_results.map { |campaign, figures| [campaign, figures[:sessions], "bg-slate-600", ChartsHelper::BAR_COLOR] }, total: sessions_total,
      changes: campaign_results.to_h { |campaign, figures| [campaign, results.(figures)] },
      x_title: "Sessions", y_title: "Campaign", label: "Sessions of the busiest campaigns in #{period}, with how engaged they were and the key events they led to")
  end

  # Counts are summed into the bucket picked; a ratio can't be, so events per
  # session stays daily.
  def analytics_event_count_chart(dates, counts, previous_counts, period, granularity, event_name)
    bucketed = ->(values, within) { values && granularity.sums_for(within, values) }
    buckets = granularity.dates(dates)
    line_chart(buckets, analytics_over_time_series(period, bucketed.(counts, period), bucketed.(previous_counts, period.previous)&.first(buckets.size)),
      y_title: "Event count", per: granularity.per, label: "#{event_name} events per #{granularity.by}")
  end

  def analytics_events_per_session_chart(dates, per_session, previous_per_session, period, event_name)
    line_chart(dates, analytics_over_time_series(period, per_session, previous_per_session), y_title: "Events per session", precision: 2,
      label: "#{event_name} events per session that had it, per day")
  end

  def analytics_realtime_chart(per_minute)
    time_chart(per_minute, label: "Active users per minute, last #{Google::Analytics::RealtimeService::MINUTES} minutes",
      y_title: "Active users", per: :minute)
  end

  def analytics_active_readers_chart(result, previous, period)
    dates = result.days.map(&:date)
    metrics = [:monthly, :weekly, :daily]
    active = [["Last 28 days", :monthly], ["Last 7 days", :weekly], ["That day", :daily]].each_with_index.map { |(name, metric), index| ChartsHelper::Series.new(name: name, values: result.days.map(&metric), color: ChartsHelper::SHARE_COLORS[index]) }
    active += active.zip(metrics).filter_map { |now, metric| analytics_earlier_series(now, previous.days.map(&metric), period, dates.size) if previous }
    line_chart(dates, active.compact,
      y_title: "Readers", label: "Readers active over the 28 days, 7 days and day to each date")
  end

  def analytics_stickiness_chart(result, previous, period)
    dates = result.days.map(&:date)
    shares = stickiness_series(result)
    shares += shares.zip(previous ? stickiness_series(previous) : []).filter_map { |now, before| analytics_earlier_series(now, before.values, period, dates.size) if before }
    line_chart(dates, shares, y_title: "Share", unit: "%",
      label: "Share of the longer span's readers who also read in the shorter one, each date")
  end

  # The period before is dotted in each step's colour and after the steps,
  # lined up under these dates.
  def analytics_funnel_trend_chart(funnel, previous, period, dates)
    colors = ChartsHelper::SHARE_COLORS
    before_dates = (period.previous.from..period.previous.to).first(dates.size) if previous
    steps_now = funnel.steps.each_with_index.map { |step, index| ChartsHelper::Series.new(name: step.name,
      values: dates.map { |date| funnel.trend[date]&.[](index) || 0 }, color: colors[index % colors.size], dashed: (true if index >= colors.size)) }
    line_chart(dates, [*steps_now,
      *(previous ? funnel.steps.each_with_index.map { |step, index| ChartsHelper::Series.new(name: "#{step.name}, #{period.previous}",
        values: dates.each_index.map { |position| (previous.trend[before_dates[position]]&.[](index) || 0 if before_dates[position]) },
        color: colors[index % colors.size], dotted: true, against: steps_now[index]) } : [])],
      y_title: "Readers", label: "#{funnel.title}: readers at each step per day")
  end

  def analytics_visitor_weeks_chart(weeks, previous_weeks, period)
    known = {"new" => ["New", ChartsHelper::SHARE_COLORS[0]], "returning" => ["Returning", ChartsHelper::SHARE_COLORS[1]]}
    types = weeks[:views].keys.sort_by { |type| [known.keys.index(type) || known.size, type] }
    stacked_chart(weeks[:weeks], types.map { |type| ChartsHelper::Series.new(name: known.dig(type, 0) || type.humanize,
        values: weeks[:views][type], color: known.dig(type, 1) || ChartsHelper::SHARE_OTHER_COLOR) },
      per: :week, y_title: "Views", label: "Each week's views from new and returning readers",
      previous: previous_weeks, previous_name: (period.previous.to_s if previous_weeks))
  end

  def analytics_page_speed_scores_chart(dates, by_day)
    line_chart(dates, page_speed_history_series(by_day, Google::PageSpeed::Result::CATEGORIES, scale: 100),
      y_title: "Score", label: "Lighthouse scores of each run")
  end

  def analytics_page_speed_lab_times_chart(dates, by_day)
    line_chart(dates, page_speed_history_series(by_day, %w[lab_lcp_ms lab_fcp_ms lab_speed_index_ms], scale: 0.001),
      y_title: "Seconds", unit: " s", label: "Lab LCP, FCP and Speed Index of each run")
  end

  def analytics_crux_metric_chart(dates, stats, metric, label)
    line_chart(dates, [ChartsHelper::Series.new(name: label, values: stats.map { |stat| stat.p75[metric] })],
      y_title: crux_unit(metric), label: "#{label}, 75th percentile, by 28-day window")
  end

  def analytics_page_speed_device_gaps_chart(device_gaps)
    dumbbell_chart(device_gaps.map { |row| [row.page_path || row.url, [row.mobile, row.desktop]] },
      keys: [["Mobile", ChartsHelper::SHARE_COLORS[1], :circle], ["Desktop", ChartsHelper::SHARE_COLORS[0], :square]],
      x_title: "Performance score", y_title: "Page", label: "Performance score on mobile and desktop for each page, widest gap first")
  end

  def analytics_page_speed_lcp_chart(pairs, good)
    colors = {"mobile" => ChartsHelper::SHARE_COLORS[1], "desktop" => ChartsHelper::SHARE_COLORS[0]}
    seconds = ->(value) { "#{number_with_precision(value, precision: 1)} s" }
    tick = ->(value) { "#{number_with_precision(value, precision: 2, strip_insignificant_zeros: true)} s" }
    x_max = round_top([*pairs.map { |result| result.lab_lcp_ms / 1000.0 }, good * 1.6].max)
    scatter_chart(pairs.map { |result| ChartsHelper::ScatterPoint.new(x: result.lab_lcp_ms / 1000.0, y: result.field_lcp_ms / 1000.0,
        color: colors[result.strategy], tip: chart_tip(result.page_path || result.url,
          [{value: seconds.(result.lab_lcp_ms / 1000.0), name: "Lab", color: colors[result.strategy]},
          {value: seconds.(result.field_lcp_ms / 1000.0), name: "Real readers"},
          {value: result.strategy.capitalize, name: "Device"}])) },
      curve: [[0, good], [good, good], [good, 0]], x_min: 0, x_max: x_max, x_ticks: [0, x_max / 4.0, x_max / 2.0, x_max * 3 / 4.0, x_max],
      x_tick: tick, y_tick: tick, x_title: "Lab LCP", y_title: "Real readers' LCP",
      label: "Lab LCP against real readers' LCP for each page, with the good limit boxed",
      key: [["Mobile", colors["mobile"]], ["Desktop", colors["desktop"]]])
  end

  def analytics_page_speed_categories_chart(category_averages, category_labels)
    dumbbell_chart(category_averages.map { |category, scores| [category_labels[category], scores.values_at("mobile", "desktop")] },
      keys: [["Mobile", ChartsHelper::SHARE_COLORS[1], :circle], ["Desktop", ChartsHelper::SHARE_COLORS[0], :square]],
      x_title: "Average score", y_title: "Category", label: "Average Lighthouse score per category on mobile and desktop")
  end

  def analytics_cohort_cell(cohort, week, share, max)
    heat_cell(number_to_percentage(share * 100, precision: 0), share * 100, max * 100, class: "h-6 min-w-11",
      tip: chart_tip("Cohort of #{l(cohort.start, format: "%a, %-d %b, %Y")}, week #{week}", [{value: number_with_delimiter(cohort.active[week]), name: "Came back, of #{number_with_delimiter(cohort.users)}"}]))
  end

  # The tip gives a cell's share of its row, which is what a row is read across for.
  def analytics_cross_tab_cell(value, max, title, metric_label, before, previous_name, row_total)
    heat_cell(number_with_delimiter(value), value, max, class: "h-6 min-w-14",
      tip: chart_tip(title,
        [*cell_readings(metric_label, value, before, previous_name),
         ({value: number_to_percentage(value * 100.0 / row_total, precision: 1), name: "Share of the row"} if row_total.to_i.positive?)]))
  end

  private

  # The period before is dashed, as in GA, so a figure is read against it.
  def analytics_over_time_series(period, current, previous)
    now = ChartsHelper::Series.new(name: period.to_s, values: current)
    [now, (ChartsHelper::Series.new(name: period.previous.to_s, values: previous, dashed: true, against: now) if previous)].compact
  end

  # Dashed in each line's own hue, as in GA, trimmed to the days shown so
  # the two share an axis.
  def analytics_earlier_series(series, values, period, size)
    ChartsHelper::Series.new(name: "#{series.name}, #{period.previous}", values: values.first(size), dashed: true, color: series.color, against: series)
  end
end
