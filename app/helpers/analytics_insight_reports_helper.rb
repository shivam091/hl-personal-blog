# encoding: UTF-8

module AnalyticsInsightReportsHelper
  SPEED_BANDS = {
    good: ["Good", ChartsHelper::SHARE_COLORS[2]],
    needs_improvement: ["Needs improvement", ChartsHelper::SHARE_COLORS[3]],
    poor: ["Poor", ChartsHelper::SHARE_COLORS[1]]
  }.freeze

  # Split is for figures GA gives by country, the only ones a period
  # compared by country can be read against.
  TrendTab = Struct.new(:field, :label, :format, :value, :previous, :split, :hint, keyword_init: true)

  def analytics_trend_tabs(insights)
    previous = insights.previous_totals
    unsplit = previous && insights.previous_unsplit?
    totals = insights.totals
    [
      TrendTab.new(field: :views, label: "Views", format: :count, value: totals.views, previous: previous&.views, split: true,
        hint: "The number of web pages your users saw. Repeated views of a single page are counted."),
      TrendTab.new(field: :engagement_rate, label: "Engagement rate", format: :rate, value: insights.landing_totals.engagement_rate,
        previous: (insights.landing_totals(insights.period.previous).engagement_rate if unsplit),
        hint: "The share of sessions that lasted over 10 seconds, had a key event, or had 2 or more page views. Every country."),
      TrendTab.new(field: :read_through, label: "Read-through rate", format: :percent, value: insights.site_read_through,
        previous: (insights.site_read_through(insights.period.previous) if unsplit),
        hint: "Finished reads the blog reports once a reader reaches an entry's end after reading a while, and GA's scroll events for " \
              "days before it sent them, as a share of views. Every country."),
      TrendTab.new(field: :key_events, label: "Key events", format: :count, value: totals.key_events, previous: previous&.key_events, split: true,
        hint: "The number of times users triggered a key event.")
    ]
  end

  def analytics_trend_series(insights, tab, dates, before, before_dates)
    scale = ->(values) { tab.format == :count ? values : values.map { |value| (value * 100).round(2) if value } }
    now = ChartsHelper::Series.new(name: "This period", values: scale.(insights.trend(tab.field, dates)))
    [now, (ChartsHelper::Series.new(name: before.to_s, values: scale.(insights.trend(tab.field, before_dates, before)).first(dates.size), dashed: true, against: now) if before)].compact
  end

  def speed_scatter_points(points)
    points.map do |point|
      color = SPEED_BANDS.fetch(Google::PageSpeed::Result.rating(:lcp_ms, point.lcp_ms)).last
      ChartsHelper::ScatterPoint.new(x: point.lcp_ms / 1000.0, y: point.engagement_rate * 100, color: color,
        tip: chart_tip(point.page_path, [
          {value: "#{number_with_precision(point.lcp_ms / 1000.0, precision: 1)} s", name: (point.source == :readers ? "Readers' mean LCP" : "LCP on a phone"),
           color: color},
          {value: metric_value(point.engagement_rate, :rate), name: "Engaged"},
          {value: number_with_delimiter(point.views), name: "Views"}
        ]))
    end
  end

  # So a reader gets a sentence rather than a bare coefficient, which is
  # kept beside it for anyone who wants the figure.
  def speed_correlation_sentence(correlation)
    figure = "(r = #{number_with_precision(correlation, precision: 2)})"
    return "Slower pages don't hold readers any less #{figure}: speed isn't what's losing them." unless correlation.negative?

    strength = if correlation.abs < 0.2 then "barely" elsif correlation.abs < 0.5 then "somewhat" else "clearly" end
    "Slower pages hold readers #{strength} less #{figure}."
  end
end
