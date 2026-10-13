# encoding: UTF-8

module CompareHelper
  Measure = Struct.new(:lower_is_better, :format)

  MORE_IS_BETTER = Measure.new(false, :count)
  LESS_IS_BETTER = Measure.new(true, :count)
  SLOWER_IS_WORSE = Measure.new(true, :milliseconds)
  LONGER_IS_WORSE = Measure.new(true, :duration)
  HIGHER_RATE_IS_BETTER = Measure.new(false, :percent)
  HIGHER_RATE_IS_WORSE = Measure.new(true, :percent)

  # A compared period can be a day longer or shorter, so its days are
  # matched by position and any left over are dropped or left empty.
  def aligned(values, size)
    Array.new(size) { |index| values[index] }
  end

  # A note on how a figure was counted stays whether or not a comparison is
  # picked; only the change depends on it.
  def noted_change(note, current, previous, measure)
    safe_join([note, metric_change(current, previous, measure)].compact, " · ")
  end

  # One series of bars, with the compared period's totals dotted over them
  # when there are any, as a stacked chart is the one that draws them.
  def compared_bars(dates, values, previous:, previous_name:, label:, y_title:, per: :day)
    return time_chart(dates.zip(values), y_title: y_title, label: label, per: per) unless previous

    stacked_chart(dates, [ChartsHelper::Series.new(name: y_title, values: values, color: ChartsHelper::BAR_COLOR)],
      previous: aligned(previous, dates.size), previous_name: previous_name, label: label, y_title: y_title, per: per)
  end
end
