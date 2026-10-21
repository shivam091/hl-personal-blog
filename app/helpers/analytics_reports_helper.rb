# encoding: UTF-8

module AnalyticsReportsHelper
  # Google's own LCP bands in the colours the charts use for good and bad,
  # so a dot's colour says how its load time rates.
  SPEED_BANDS = {
    good: ["Good", ChartsHelper::SHARE_COLORS[2]],
    needs_improvement: ["Needs improvement", ChartsHelper::SHARE_COLORS[3]],
    poor: ["Poor", ChartsHelper::SHARE_COLORS[1]]
  }.freeze

  def speed_scatter_points(points)
    points.map do |point|
      color = SPEED_BANDS.fetch(Google::PageSpeed::Result.rating(:lcp_ms, point.lcp_ms)).last
      ChartsHelper::ScatterPoint.new(x: point.lcp_ms / 1000.0, y: point.engagement_rate * 100, color: color,
        tip: chart_tip(point.page_path, [
          {value: "#{number_with_precision(point.lcp_ms / 1000.0, precision: 1)} s", name: (point.source == :readers ? "readers' mean LCP" : "LCP on a phone"),
           color: color},
          {value: metric_value(point.engagement_rate, :rate), name: "engaged"},
          {value: number_with_delimiter(point.views), name: "views"}
        ]))
    end
  end

  # Worded for a reader rather than as a coefficient, which is kept beside
  # it for anyone who wants the figure.
  def speed_correlation_sentence(correlation)
    figure = "(r = #{number_with_precision(correlation, precision: 2)})"
    return "Slower pages don't hold readers any less #{figure}: speed isn't what's losing them." unless correlation.negative?

    strength = if correlation.abs < 0.2 then "barely" elsif correlation.abs < 0.5 then "somewhat" else "clearly" end
    "Slower pages hold readers #{strength} less #{figure}."
  end
end
