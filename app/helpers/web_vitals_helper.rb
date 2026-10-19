# encoding: UTF-8

module WebVitalsHelper
  WEB_VITAL_RATING_CLASSES = {
    good: "text-emerald-700",
    needs_improvement: "text-amber-700",
    poor: "font-medium text-red-700"
  }.freeze
  CRUX_METRIC_LABELS = {
    "lcp" => "Largest Contentful Paint",
    "inp" => "Interaction to Next Paint",
    "cls" => "Cumulative Layout Shift",
    "fcp" => "First Contentful Paint",
    "ttfb" => "Time to First Byte"
  }.freeze
  # Only these three count towards Google's pass or fail; FCP and TTFB are
  # shown because they explain a slow LCP.
  CORE_WEB_VITALS = %w[lcp inp cls].freeze

  def web_vital_rating_class(rating)
    WEB_VITAL_RATING_CLASSES[rating]
  end

  def crux_metric_label(metric)
    CRUX_METRIC_LABELS.fetch(metric)
  end

  def core_web_vital?(metric)
    CORE_WEB_VITALS.include?(metric)
  end

  # CLS is a unitless score, every other metric a time.
  def crux_value(metric, value)
    return "—" if value.nil?

    metric == "cls" ? number_with_precision(value, precision: 2) : "#{number_with_delimiter(value.round)} ms"
  end

  def crux_unit(metric)
    metric == "cls" ? "CLS" : "ms"
  end
end
