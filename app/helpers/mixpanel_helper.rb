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

  READING_TIME_COLORS = [ChartsHelper::SHARE_OTHER_COLOR, *ChartsHelper::SHARE_COLORS.values_at(3, 2, 0)].freeze

  # Numbered when there are several, so each opens a different session.
  def mixpanel_replay_links(replays, label: "Watch")
    links = Array(replays).filter_map { |replay| (url = mixpanel_client.replay_url(replay)) && [replay, url] }
    return if links.empty?

    safe_join(links.each_with_index.map do |(replay, url), index|
      link_to(url, target: "_blank", rel: "noopener", title: mixpanel_replay_title(replay),
        class: "inline-flex items-center gap-0.5 font-medium whitespace-nowrap text-slate-700 underline hover:text-slate-900") do
        safe_join([icon("play", size: 12), links.one? ? label : "#{label} #{index + 1}"], " ")
      end
    end, " ")
  end

  def mixpanel_reading_time_parts
    Mixpanel::PageStat::READING_TIMES.values.map(&:first).zip(READING_TIME_COLORS)
  end

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

  def mixpanel_replay_title(replay)
    at = Time.zone.at(replay["time"].to_i) if replay["time"].to_i.positive?
    parts = ["Open this session's replay in Mixpanel", (l(at, format: "%-d %b, %H:%M") if at), ("#{replay["seconds"]}s active" if replay["seconds"])]
    parts.compact.join(" · ")
  end

  def mixpanel_client
    @mixpanel_client ||= Mixpanel::Client.new
  end

  def mixpanel_engaged_chart(report, granularity, label:, path: nil)
    line_chart(granularity.dates(report.dates),
      [ChartsHelper::Series.new(name: "Engaged seconds per view", values: report.mean_engaged_seconds_by(granularity, path: path))],
      y_title: "Seconds", unit: "s", label: label, per: granularity.per)
  end
end
