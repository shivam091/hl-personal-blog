# encoding: UTF-8

module PageSpeedHelper
  # Lighthouse's own bands, so a score is coloured as PageSpeed Insights
  # colours it.
  def lighthouse_score_class(score)
    if score.nil? then "text-slate-400"
    elsif score >= 0.9 then "text-emerald-700"
    elsif score >= 0.5 then "text-amber-700"
    else "font-medium text-red-700"
    end
  end

  # CrUX's overall verdict in the words and colours its per-metric ratings
  # use here, so the two read alike.
  FIELD_CATEGORIES = {
    "FAST" => ["Fast", :good], "AVERAGE" => ["Average", :needs_improvement], "SLOW" => ["Slow", :poor]
  }.freeze

  def field_category_label(category)
    label, rating = FIELD_CATEGORIES[category]
    return tag.span("—", class: "text-slate-400", title: "Too few Chrome users for Google to say") unless label

    tag.span(label, class: web_vital_rating_class(rating))
  end

  # In the units PageSpeed Insights writes each lab figure in, so the two
  # can be read side by side.
  def lab_value(field, value)
    if value.nil? then "—"
    elsif field == :lab_cls then number_with_precision(value, precision: 3, strip_insignificant_zeros: true)
    elsif field == :lab_tbt_ms then "#{number_with_delimiter(value.round)} ms"
    else "#{number_with_precision(value / 1000.0, precision: 1)} s"
    end
  end

  HISTORY_LABELS = {
    "performance" => "Performance", "accessibility" => "Accessibility", "best_practices" => "Best practices", "seo" => "SEO",
    "lab_lcp_ms" => "LCP", "lab_fcp_ms" => "FCP", "lab_speed_index_ms" => "Speed Index"
  }.freeze

  # Scaled to the axis's unit, since scores are kept 0 to 1 and times in ms.
  def page_speed_history_series(runs_by_day, fields, scale:)
    fields.each_with_index.map do |field, index|
      ChartsHelper::Series.new(name: HISTORY_LABELS.fetch(field), color: ChartsHelper::SHARE_COLORS[index],
        values: runs_by_day.values.map { |run| run[field] && (run[field] * scale).round(2) })
    end
  end

  # The same bands as a filled cell, so a grid of scores reads by colour.
  def lighthouse_cell_class(score)
    if score.nil? then "bg-slate-50 text-slate-400"
    elsif score >= 0.9 then "bg-emerald-100 text-emerald-800"
    elsif score >= 0.5 then "bg-amber-100 text-amber-800"
    else "bg-red-100 font-medium text-red-800"
    end
  end
end
