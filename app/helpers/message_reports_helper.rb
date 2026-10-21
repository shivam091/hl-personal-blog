# encoding: UTF-8

module MessageReportsHelper
  # Green and orange from the chart palette, so verdicts read the same in
  # every chart; unmarked is the palette's neutral, as it isn't a verdict.
  VERDICT_SERIES = {
    "genuine" => ["Genuine", ChartsHelper::SHARE_COLORS[2]],
    "spam" => ["Spam", ChartsHelper::SHARE_COLORS[1]],
    "unmarked" => ["Not marked", ChartsHelper::SHARE_OTHER_COLOR]
  }.freeze

  FEEDBACK = {
    reported: ["Reported to Google", "check-circle", "text-emerald-600"],
    sending: ["Sending", "clock", "text-slate-400"],
    failed: ["Failed to send", "alert-triangle", "text-red-500"],
    unreportable: ["No assessment to report", "info", "text-slate-400"],
    unmarked: ["Not marked yet", "inbox", "text-slate-400"]
  }.freeze

  def verdict_series(counts)
    VERDICT_SERIES.map do |verdict, (name, color)|
      ChartsHelper::Series.new(name: name, values: counts.fetch(verdict), color: color)
    end
  end

  def band_series(bands)
    verdict_series(
      "genuine" => bands.map(&:genuine),
      "spam" => bands.map(&:spam),
      "unmarked" => bands.map(&:unmarked)
    )
  end

  def share_or_dash(share)
    share ? number_to_percentage(share * 100, precision: 0) : "—"
  end

  def score_or_dash(score)
    score ? format("%.2f", score) : "—"
  end
end
