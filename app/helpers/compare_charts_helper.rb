# encoding: UTF-8

module CompareChartsHelper
  # Bars stay as they are with nothing to compare; once there is, a second
  # line is the only way to draw a whole earlier period on the same days.
  def compared_time_chart(points, previous:, previous_name:, label:, y_title:, **options)
    return time_chart(points, label: label, y_title: y_title, **options) unless previous

    keys = points.map(&:first)
    current = ChartsHelper::Series.new(name: "This period", values: points.map(&:last))
    line_chart(keys,
      [current,
       ChartsHelper::Series.new(name: previous_name, values: aligned(previous, keys.size), dashed: true, against: current)],
      label: "#{label}, against #{previous_name}", y_title: y_title, per: options.fetch(:per, :day),
      events: options.fetch(:events, {}), event_name: options[:event_name])
  end

  # The chart's own key gives each slice's count and share; what an earlier
  # period adds is how each moved, which an arc can't show.
  def donut_comparison(counts, previous, unit:, previous_name:)
    rows = counts.map { |key, count| [key.to_s, count.to_i] }.reject { |_, count| count.zero? }.sort_by { |key, count| [-count, key] }
    return if rows.empty?

    shown = rows.size > ChartsHelper::DONUT_SLICES ? rows.first(ChartsHelper::DONUT_SLICES - 1) : rows
    rest = rows.drop(shown.size)
    slices = shown + (rest.any? ? [["Other", rest.sum(&:last)]] : [])
    before = previous.transform_keys(&:to_s)
    before_total = before.values.sum.to_f
    other_before = before.reject { |key, _| shown.any? { |name, _| name == key } }.values.sum
    tag.div(class: "mt-3 border-t border-slate-100 pt-2 text-xs") do
      safe_join([
        tag.p("Against #{previous_name}", class: "mb-1 font-medium text-slate-500"),
        tag.ul(class: "space-y-1") do
          safe_join(slices.map do |name, count|
            earlier = name == "Other" && rest.any? ? other_before : before.fetch(name, 0)
            share = before_total.positive? ? number_to_percentage(earlier / before_total * 100, precision: 1) : "—"
            tag.li(class: "flex items-center justify-between gap-3") do
              safe_join([
                tag.span(name, class: "min-w-0 truncate text-slate-700", title: name),
                tag.span(class: "whitespace-nowrap tabular-nums text-slate-500") do
                  safe_join(["#{number_with_delimiter(earlier)} #{unit.pluralize(earlier)} · #{share}", row_change(count, earlier, CompareHelper::MORE_IS_BETTER)], " ")
                end
              ])
            end
          end)
        end
      ])
    end
  end

  # A cell's figure beside the one for the period compared with, so a cell is
  # read against itself.
  def cell_readings(metric, current, previous, previous_name)
    return [{value: number_with_delimiter(current), name: metric}] unless previous

    compared_readings(metric, number_with_delimiter(current), number_with_delimiter(previous), previous_name, current_value: current, before_value: previous)
  end
end
