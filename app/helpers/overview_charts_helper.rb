module OverviewChartsHelper
  def overview_trend_chart(insights, tab, dates, compared, before_dates, granularity, events)
    line_chart(dates, analytics_trend_series(insights, tab, dates, compared, before_dates), y_title: tab.label,
      unit: (tab.format == :count ? "" : "%"), per: granularity.per, events: events, event_name: "Published",
      label: "#{tab.label} per #{granularity.by}#{", against #{compared}" if compared}")
  end

  def overview_speed_scatter_chart(points, x_max, readers)
    scatter_chart(speed_scatter_points(points), x_min: 0, x_max: x_max, x_ticks: [0, x_max / 2.0, x_max],
      x_tick: ->(seconds) { "#{number_with_precision(seconds, precision: 1, strip_insignificant_zeros: true)} s" },
      y_tick: ->(rate) { "#{rate.round}%" }, x_title: (readers ? "Readers' mean LCP" : "Lab LCP on a phone"), y_title: "Engagement rate",
      label: "Each page's load time on a phone against its engagement rate", key: AnalyticsInsightReportsHelper::SPEED_BANDS.values)
  end

  def overview_day_of_week_chart(days)
    time_chart(days.map { |day, views| [Google::DailyReport.value_label(:day_of_week, day), views] }, x_title: "Day", y_title: "Views",
      label: "Views by day of week")
  end

  def overview_hour_of_day_chart(hours)
    time_chart(hours.map { |hour, views| [Google::DailyReport.value_label(:hour, hour), views] }, x_title: "Hour", y_title: "Views",
      label: "Views by hour of day")
  end

  def overview_calls_by_service_chart(calls, before, vs)
    stacked_chart(calls.dates, share_series(calls.daily_by_service) { |service| service },
      y_title: "Calls", label: "External calls per day, split by service",
      previous: (aligned(before.daily_totals, calls.dates.size) if before), previous_name: vs)
  end

  def overview_failed_calls_chart(calls, before, vs)
    compared_bars(calls.dates, calls.daily_failed, previous: before&.daily_failed, previous_name: vs, y_title: "Failed calls", label: "Failed external calls per day")
  end

  def overview_funnel_chart(content, before, vs)
    funnel_chart(content.funnel, label: "Entries at each step from published to read", unit: "entry", previous: before&.funnel, previous_name: vs)
  end

  def overview_decay_chart(points, colors, x_max)
    scatter_chart(points.map { |point| ChartsHelper::ScatterPoint.new(x: point.age_months, y: point.item.views, color: colors[point.item.type],
        tip: chart_tip(point.item.entry.name, [{value: number_with_delimiter(point.item.views), name: "Views", color: colors[point.item.type]},
          {value: l(point.item.entry.published_at.to_date), name: "Published"}, {value: point.item.type.capitalize, name: "Type"}])) },
      x_min: 0, x_max: x_max, x_ticks: [0, x_max / 4.0, x_max / 2.0, x_max * 3 / 4.0, x_max],
      x_tick: ->(months) { number_with_precision(months, precision: 1, strip_insignificant_zeros: true) }, y_tick: ->(views) { compact_number(views) },
      x_title: "Months since publishing", y_title: "Views", label: "Views in the period against each entry's age",
      key: colors.map { |type, color| [type.pluralize.capitalize, color] })
  end

  def overview_updates_chart(updates, content)
    ranking_chart(updates.bands.map { |band, count| [band, count, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: content.items.size, x_title: "Entries", y_title: "Latest update", label: "Entries by how long after publishing they were last updated")
  end

  def overview_tags_chart(rows, earlier_tags, vs)
    ranking_chart(rows.sort_by { |row| [-row[:average_views], row[:tag]] }.map { |row| [row[:tag], row[:average_views].round, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: nil, x_title: "Views per entry", y_title: "Tag", label: "Views per entry for each of the most viewed tags",
      previous: earlier_tags&.transform_values { |row| row[:average_views].round }, previous_name: vs)
  end

  def overview_categories_chart(rows, earlier_categories, vs)
    ranking_chart(rows.sort_by { |row| [-row[:average_views], row[:category]] }.map { |row| [row[:category], row[:average_views].round, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: nil, x_title: "Views per entry", y_title: "Category", label: "Views per entry for each category",
      previous: earlier_categories&.transform_values { |row| row[:average_views].round }, previous_name: vs)
  end

  def overview_gaps_chart(recent, gaps_type)
    time_chart(recent.map { |gap| [gap.to, gap.days] }, y_title: "Days since the one before", x_title: "Publishing day",
      label: "Days since the publishing day before, for each publishing day in the last year#{" with a #{gaps_type}" if gaps_type}")
  end

  def overview_own_vs_analytics_chart(granularity, dates, stats, analytics)
    line_chart(granularity.dates(dates), [ChartsHelper::Series.new(name: "Blog's own count", values: granularity.sums(dates, stats.daily(:views))),
      ChartsHelper::Series.new(name: "Google Analytics", values: granularity.sums(dates, analytics.daily_views), dashed: true)],
      y_title: "Views", label: "The blog's own views against Google Analytics views, per #{granularity.by}", per: granularity.per)
  end

  def overview_audience_chart(dates, stats, visitors, views, counted, before)
    stacked_chart(dates,
      [ChartsHelper::Series.new(name: "Unique visitors", values: dates.each_index.map { |i| visitors[i] if counted[i] }, color: ChartsHelper::SHARE_COLORS[0]),
        ChartsHelper::Series.new(name: "Repeat views", values: dates.each_index.map { |i| [views[i] - visitors[i], 0].max if counted[i] }, color: ChartsHelper::SHARE_COLORS[1])],
      y_title: "Views", label: "Each day's views split into unique visitors and repeat views#{", against #{before}" if before}",
      previous: (aligned(stats.daily(:views, before), dates.size) if before), previous_name: before&.to_s)
  end

  def overview_search_clicks_chart(granularity, days, search, published)
    time_chart(granularity.dates(days).zip(granularity.sums(days, search.daily(:clicks))), y_title: "Clicks", label: "Search clicks per #{granularity.by}",
      per: granularity.per, events: granularity.events(published), event_name: "Published", unsettled: search_unsettled_from)
  end

  def overview_subscriber_totals_chart(dates, stats, before, published)
    compared_time_chart(dates.zip(stats.subscriber_totals), y_title: "Subscribers", label: "Newsletter list size per day", style: :line,
      events: published, event_name: "Published", previous_name: before.to_s, previous: (stats.subscriber_totals(before) if before))
  end

  def overview_new_subscribers_chart(stats, before, published)
    compared_time_chart(stats.weekly(:subscribers).to_a, y_title: "New subscribers", label: "New subscribers by week", per: :week,
      events: weekly_events(published), event_name: "Published", previous_name: before.to_s,
      previous: (stats.weekly(:subscribers, before).values if before))
  end

  def overview_views_chart(granularity, dates, days, stats, before, events)
    views_now = ChartsHelper::Series.new(name: "This period", values: granularity.sums(days, stats.daily(:views)))
    line_chart(dates, [views_now,
      (ChartsHelper::Series.new(name: before.to_s, values: granularity.sums_for(before, stats.daily(:views, before)).first(dates.size), dashed: true, against: views_now) if before)].compact,
      y_title: "Views", label: "Views per #{granularity.by}#{", against #{before}" if before}", per: granularity.per, events: events, event_name: "Published")
  end

  def overview_likes_chart(granularity, dates, days, stats, likes_before, events)
    compared_time_chart(dates.zip(granularity.sums(days, stats.daily(:likes))), y_title: "Likes", label: "Likes per #{granularity.by}", per: granularity.per,
      events: events, event_name: "Published", previous_name: likes_before.to_s,
      previous: (granularity.sums_for(likes_before, stats.daily(:likes, likes_before)) if likes_before))
  end

  def overview_own_vs_ga_chart(buckets, lines, granularity)
    line_chart(buckets, lines, per: granularity.per,
      y_title: "Views", label: "The blog's own views against Google Analytics views, per #{granularity.by}")
  end

  def overview_waiting_chart(coverage, waiting)
    ranking_chart(coverage.waiting_ages.map { |bucket, count| [bucket, count, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: waiting.size, x_title: "Pages", y_title: "Waiting", label: "Pages not indexed, by how long they've waited")
  end

  def overview_notified_entries_chart(entries)
    stacked_chart(entries.map { |entry| entry.notified_at.to_date },
      [ChartsHelper::Series.new(name: "Delivered", values: entries.map(&:notified_count), color: ChartsHelper::SHARE_COLORS[0]),
        ChartsHelper::Series.new(name: "Undelivered", values: entries.map { |entry| entry.notification_failures.size }, color: ChartsHelper::SHARE_COLORS[1])],
      titles: entries.map(&:name), x_title: "Sent", y_title: "Emails", label: "Subscriber emails delivered and undelivered for each entry sent")
  end
end
