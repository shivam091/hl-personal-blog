# encoding: UTF-8

module ExternalCallsHelper
  # Google reports run to seconds while a feed fetch takes milliseconds, so
  # the unit follows the figure.
  def call_duration(call)
    ms = call.duration_ms.to_f
    ms >= 1000 ? "#{number_with_precision(ms / 1000, precision: 2)} s" : "#{number_with_precision(ms, precision: 0)} ms"
  end

  # Higher than a page's thresholds, since a report legitimately takes a while.
  def call_duration_class(call)
    if call.duration_ms.to_f >= 10_000 then "text-red-700 font-medium"
    elsif call.duration_ms.to_f >= 3_000 then "text-amber-700"
    else "text-slate-600"
    end
  end
end
