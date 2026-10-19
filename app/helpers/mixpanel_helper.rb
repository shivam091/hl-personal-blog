# encoding: UTF-8

module MixpanelHelper
  # Fixed per status and kind, so the dashboard, the report and a page's
  # view colour each the same way.
  GA_STATUS_SERIES = {
    "loaded" => ["GA loaded", ChartsHelper::SHARE_COLORS[0]],
    "blocked" => ["GA blocked", ChartsHelper::SHARE_COLORS[1]],
    "off" => ["GA off", ChartsHelper::SHARE_COLORS[3]],
    "unknown" => ["Not yet known", ChartsHelper::SHARE_OTHER_COLOR]
  }.freeze
  FRUSTRATION_SERIES = {
    rage_clicks: ["Rage clicks", ChartsHelper::SHARE_COLORS[1]],
    dead_clicks: ["Dead clicks", ChartsHelper::SHARE_COLORS[3]],
    js_errors: ["Script errors", ChartsHelper::SHARE_COLORS[4]]
  }.freeze

  def mixpanel_ga_status_series(report, granularity)
    GA_STATUS_SERIES.map do |status, (name, color)|
      ChartsHelper::Series.new(name: name, color: color, values: granularity.sums(report.dates, report.ga_daily(status)))
    end
  end

  def mixpanel_frustration_series(report, granularity, path: nil)
    FRUSTRATION_SERIES.map do |field, (name, color)|
      ChartsHelper::Series.new(name: name, color: color, values: granularity.sums(report.dates, report.page_daily(field, path: path)))
    end
  end

  def mixpanel_reading_series(report, granularity, path: nil)
    [
      ChartsHelper::Series.new(name: "Read through", values: report.read_through_percent_by(granularity, path: path)),
      ChartsHelper::Series.new(name: "Mean scroll depth", values: report.mean_scroll_percent_by(granularity, path: path), dashed: true)
    ]
  end

  def mixpanel_engaged_chart(report, granularity, label:, path: nil)
    line_chart(granularity.dates(report.dates),
      [ChartsHelper::Series.new(name: "Engaged seconds per view", values: report.mean_engaged_seconds_by(granularity, path: path))],
      y_title: "Seconds", unit: "s", label: label, per: granularity.per)
  end
end
