# encoding: UTF-8

module SearchChartsHelper
  def search_rows_over_time_chart(chart, series, label:, total:, unsettled:)
    per = chart.plotting.by
    line_chart(chart.dates, series, y_title: label, label: "#{label} per #{per} for the charted rows#{" and in total" if total}", selectable: true, per: per.to_sym,
      unsettled: unsettled)
  end

  def search_rows_ranking_chart(chart, label:, headings:, total:, offset:)
    ranking_chart(chart.rows.zip(ChartsHelper::SHARE_SWATCHES, ChartsHelper::SHARE_COLORS, ChartsHelper::ROW_MARKERS).map { |row, swatch, color, marker| [row.label, row.value, swatch, color, marker] },
      x_title: label, y_title: headings.join(" · "), label: "#{label} of the charted rows, with each one's share of the total", total: total, first_series: offset,
      previous: (chart.rows.to_h { |row| [row.label, row.previous_value] } if chart.previous_name), previous_name: chart.previous_name)
  end

  def search_trend_chart(trend, measures, unsettled:)
    measures_chart(trend.dates, measures, label: "#{measures.map(&:name).to_sentence} per #{trend.per}, each on its own scale", per: trend.per.to_sym,
      unsettled: unsettled)
  end

  def search_shares_chart(shares, y_title:, key_label:, split:, empty: nil)
    share_chart(shares, y_title: y_title, key_label: key_label, empty: empty || "No views in this period.",
      label: "Each #{shares[:unit]}'s views split by #{split}, as a share of that #{shares[:unit]}")
  end

  def search_login_attempts_chart(daily, days)
    stacked_chart(daily.map(&:first),
      [ChartsHelper::Series.new(name: "Accepted", values: daily.map(&:second), color: "#2a78d6"),
       ChartsHelper::Series.new(name: "Rejected", values: daily.map(&:third), color: "#eb6834")],
      label: "Login attempts per day, #{days}, accepted and rejected", y_title: "Attempts")
  end

  def search_login_scores_chart(groups)
    stacked_chart(Google::Recaptcha::Summary::BUCKETS,
      [ChartsHelper::Series.new(name: "Right password", values: groups["CORRECT_PASSWORD"], color: "#2a78d6"),
       ChartsHelper::Series.new(name: "Wrong password", values: groups["INCORRECT_PASSWORD"], color: "#eb6834"),
       ChartsHelper::Series.new(name: "Not checked", values: groups[nil], color: ChartsHelper::SHARE_OTHER_COLOR)],
      label: "Login attempts by score, 0 likely a bot, 1 likely a person, split by password", x_title: "Score", y_title: "Attempts")
  end

  def search_recaptcha_requests_chart(report, scope, low_score, period)
    stacked_chart(report.daily.map(&:first),
      [ChartsHelper::Series.new(name: "High risk (below #{low_score})", values: report.daily.map(&:second), color: "#0d366b"),
       ChartsHelper::Series.new(name: "Low risk", values: report.daily.map(&:third), color: "#3987e5")],
      label: "Requests per day for #{scope}, split by risk", y_title: "Requests",
      previous: report.previous_daily, previous_name: Period::COMPARES[period.compare])
  end

  def search_recaptcha_scores_chart(report, scope, period)
    time_chart(report.histogram.to_a, label: "Requests by score for #{scope}, 0 likely a bot, 1 likely a person",
      x_title: "Score", y_title: "Requests", legend: "Requests",
      previous: report.previous_histogram, previous_name: Period::COMPARES[period.compare])
  end

  def search_recaptcha_actions_chart(rows, title:, total:, previous:, swatch:, color:, lower_is_better:, period:)
    change = Google::DailyReport::Metric.new(lower_is_better: lower_is_better)
    ranking_chart(rows.map { |name, count| [name, count, swatch, color] }, label: "#{title} by requests in #{period}",
      total: total, x_title: "Requests", y_title: "Action", previous: previous, previous_name: period.previous.to_s,
      changes: (rows.to_h { |name, count| [name, row_change(count, previous[name], change)] } if previous) || {})
  end

  def search_recaptcha_challenges_chart(report, challenges, period)
    stacked_chart(challenges.map(&:first),
      [ChartsHelper::Series.new(name: "No challenge needed", values: challenges.map(&:second), color: "#9ec5f4"),
       ChartsHelper::Series.new(name: "Passed", values: challenges.map(&:third), color: "#2a78d6"),
       ChartsHelper::Series.new(name: "Failed", values: challenges.map(&:fourth), color: "#eb6834")],
      label: "Checkbox challenges per day for the whole site: cleared without one, passed and failed", y_title: "Requests",
      previous: report.previous_daily_challenges, previous_name: Period::COMPARES[period.compare])
  end

  def search_ai_impressions_chart(granularity, days, daily, previous_daily, before)
    impressions_now = ChartsHelper::Series.new(name: "This period", values: granularity.sums(days, days.map { |day| daily[day] }))
    line_chart(granularity.dates(days), [impressions_now,
      (ChartsHelper::Series.new(name: before.to_s, values: granularity.sums_for(before, (before.from..before.to).map { |day| previous_daily[day] }).first(granularity.dates(days).size), dashed: true, against: impressions_now) if before)].compact,
      y_title: "Impressions", per: granularity.per,
      label: "AI Overviews and AI Mode impressions per #{granularity.by}#{", against #{before}" if before}")
  end

  def search_ai_share_chart(shared_days, daily, organic_daily)
    line_chart(shared_days, [ChartsHelper::Series.new(name: "AI share", values: shared_days.map { |day| daily[day] * 100.0 / organic_daily[day] })],
      y_title: "Share of impressions", unit: "%", precision: 1, label: "AI Overviews and AI Mode impressions as a share of the day's search impressions")
  end

  def search_ai_top_pages_chart(top_pages, row_total)
    ranking_chart(top_pages.map { |row| [row.label.sub(%r{\Ahttps?://[^/]+}i, "").presence || "/", row.impressions, "bg-slate-600", ChartsHelper::BAR_COLOR] },
      total: row_total.to_i, x_title: "Impressions", y_title: "Page", label: "The ten pages with the most AI impressions in the latest upload")
  end

  def search_position_chart(buckets, total)
    ranking_chart(buckets.map { |name, count| [name, count, "bg-slate-600", ChartsHelper::BAR_COLOR] }, total: total,
      x_title: "Impressions", y_title: "Average position", label: "Impressions of the period's queries by their average position")
  end

  def search_sitemap_urls_chart(history)
    line_chart(history.keys, [ChartsHelper::Series.new(name: "Submitted", values: history.values.map { |day| day[:submitted] }),
      ChartsHelper::Series.new(name: "Indexed", dashed: true, values: history.values.map { |day| day[:indexed] })],
      y_title: "URLs", label: "URLs submitted in the sitemaps and found indexed, by day")
  end

  def search_sitemap_issues_chart(history)
    line_chart(history.keys, [ChartsHelper::Series.new(name: "Errors", values: history.values.map { |day| day[:errors] }),
      ChartsHelper::Series.new(name: "Warnings", dashed: true, values: history.values.map { |day| day[:warnings] })],
      y_title: "Issues", label: "Sitemap errors and warnings, by day")
  end

  def search_delay_chart(delays, x_title:, label:)
    time_chart(delays.counts.to_a, x_title: x_title, y_title: "Entries", label: label)
  end

  def search_coverage_chart(coverage_counts)
    ranking_chart(coverage_counts.map { |row| [row.coverage_state, row.count, *verdict_chart_color(row.verdict)] },
      total: coverage_counts.sum(&:count), x_title: "Pages", y_title: "Coverage", label: "Inspected pages by coverage state, coloured by verdict")
  end

  def search_page_indexing_chart(indexing)
    colors = {"not_indexed" => "#a8a7a1", "indexed" => "#1baf7a"}
    names = {"not_indexed" => "Not indexed", "indexed" => "Indexed"}
    series = (indexing.shown - ["impressions"]).map { |key| ChartsHelper::Series.new(name: names[key], values: indexing.daily[key], color: colors[key]) }
    impressions = ChartsHelper::Measure.new(name: "Impressions", values: indexing.impressions, color: "#86198f", whole: true,
      tick: ->(value) { compact_number(value) }, reading: ->(value) { number_with_delimiter(value) })
    line = impressions if indexing.shown?("impressions")
    stacked_chart(indexing.dates, series, y_title: "Pages", line: line, label: "Pages indexed and not indexed each day, as the last inspection by then found them, and Google search impressions")
  end
end
