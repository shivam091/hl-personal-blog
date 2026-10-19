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

  # The same bands as a filled cell, so a grid of scores reads by colour.
  def lighthouse_cell_class(score)
    if score.nil? then "bg-slate-50 text-slate-400"
    elsif score >= 0.9 then "bg-emerald-100 text-emerald-800"
    elsif score >= 0.5 then "bg-amber-100 text-amber-800"
    else "bg-red-100 font-medium text-red-800"
    end
  end
end
