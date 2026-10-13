# encoding: UTF-8

# Inline SVG drawn on the server, so charts need no chart library, no
# third-party script in the CSP, and render in specs like any other markup.
module ChartsHelper
  CHART_HEIGHT = 120
  CHART_WIDTH = 600
  COMPACT_UNITS = {thousand: "K", million: "M", billion: "B"}.freeze
  # Enough dates to place any day without the labels crowding each other in
  # a narrow card.
  MAX_TICKS = 6
  # Fewer than this leaves too few dates to place a point by, so an axis
  # whose ends can't both be labelled at an even step drops the first end.
  MIN_TICKS = 4
  # About half a date label's width, so a label nearer the edge than this is
  # pinned inside rather than centred and cut off.
  EDGE_LABEL_ROOM = 7

  # A single hue so darker plainly reads as more; written out in full so
  # Tailwind's scan finds them.
  HEAT_CLASSES = [
    "bg-slate-100 text-slate-700", "bg-slate-200 text-slate-800", "bg-slate-300 text-slate-900",
    "bg-slate-500 text-white", "bg-slate-700 text-white", "bg-slate-900 text-white"
  ].freeze

  # A single hue so darker plainly reads as more. Zero gets a neutral grey
  # rather than the lightest step, so "none" never reads as "a little".
  MAP_FILLS = %w[fill-[#cde2fb] fill-[#9ec5f4] fill-[#6da7ec] fill-[#3987e5] fill-[#256abf] fill-[#184f95] fill-[#0d366b]].freeze
  MAP_SWATCHES = %w[bg-[#cde2fb] bg-[#9ec5f4] bg-[#6da7ec] bg-[#3987e5] bg-[#256abf] bg-[#184f95] bg-[#0d366b]].freeze
  MAP_EMPTY_FILL = "fill-[#f0efec]"
  # Long enough that the order the countries appear in can be seen.
  MAP_REVEAL_MS = 700

  # In the order validated for touching segments; Other is a neutral at the
  # base so it never sits against the last hue.
  SHARE_COLORS = %w[#2a78d6 #eb6834 #1baf7a #eda100 #e87ba4].freeze
  SHARE_FILLS = %w[fill-[#2a78d6] fill-[#eb6834] fill-[#1baf7a] fill-[#eda100] fill-[#e87ba4]].freeze
  SHARE_SWATCHES = %w[bg-[#2a78d6] bg-[#eb6834] bg-[#1baf7a] bg-[#eda100] bg-[#e87ba4]].freeze
  SHARE_OTHER_COLOR = "#a8a7a1"
  SHARE_OTHER_FILL = "fill-[#a8a7a1]"
  SHARE_OTHER_SWATCH = "bg-[#a8a7a1]"
  # Past this a slice grows too thin to judge, so the rest fold into Other.
  DONUT_SLICES = 5

  # Shapes as well as colours, so a line is told from its neighbours by more
  # than hue.
  # Kept to a 10×10 box, since the chart tooltip copies these paths.
  MARKERS = {
    circle: "M5 .5a4.5 4.5 0 1 1 0 9a4.5 4.5 0 1 1 0-9z", square: "M1 1h8v8H1z", diamond: "M5 0l5 5-5 5-5-5z",
    triangle_down: "M0 1h10L5 9.5z", triangle: "M5 .5L10 9H0z", drop: "M5 0C5 0 9 4.6 9 6.5a4 4 0 0 1-8 0C1 4.6 5 0 5 0z"
  }.freeze
  ROW_MARKERS = %i[circle square diamond triangle_down triangle].freeze
  TOTAL_MARKER = :drop
  # Fainter, so the period compared with reads as backdrop to the current one.
  EARLIER_OPACITY = 0.6

  # Hex copies of slate-800, slate-400 and slate-600, because the tooltip's
  # keys need raw colours yet must match the drawn marks.
  LINE_COLORS = %w[#1e293b #94a3b8].freeze
  BAR_COLOR = "#475569"
  # A hue no line uses, so a day's event isn't read as one of the series.
  EVENT_COLOR = "#eb6834"
  EVENT_MARKER = :triangle

  # Named for what each date in a run stands for, so a week's point isn't
  # read as a single day's.
  DATE_AXIS_TITLES = {minute: "Time", hour: "Hour", day: "Date", week: "Week starting", month: "Month"}.freeze
  DATE_AXIS_FORMATS = {minute: "%H:%M", month: "%b %Y"}.freeze
  # Clock steps a single day's hours are labelled at, so labels fall on round hours.
  HOUR_STEPS = [1, 2, 3, 4, 6, 8, 12].freeze
  UNSETTLED_NOTE = "Data is still being collected"

  # Dash as well as shade, so a second series never relies on colour alone.
  Series = Struct.new(:name, :values, :dashed, :color, :dotted, :marker, :against, :metric, :keys, keyword_init: true) do
    def dasharray
      if dotted then "0 4"
      elsif dashed then "4 3"
      end
    end
  end

  # Each on its own scale because clicks and impressions differ a
  # thousandfold, so a shared axis would flatten one into the floor. A
  # position is inverted so up still reads as better, since 1 is the top.
  Measure = Struct.new(:name, :values, :color, :dashed, :inverted, :whole, :tick, :reading, :previous, :previous_name, keyword_init: true)

  ScatterPoint = Struct.new(:x, :y, :color, :tip, keyword_init: true)

  def compact_number(value)
    number_to_human(value, format: "%n%u", units: COMPACT_UNITS, precision: 3, significant: true)
  end

  # Stretched to its box so one drawing fits any size. A nil is a stretch with
  # too little to go on, left as a break in the line rather than drawn as zero,
  # and a series reaching below zero is drawn down to its lowest value.
  def sparkline(values, label:, width: 80, height: 24)
    known = values.compact
    return tag.span("—", class: "text-slate-400") if known.empty? || known.all?(&:zero?)

    low = [known.min, 0].min.to_f
    span = [known.max, 0].max.to_f - low
    span = 1.0 if span.zero?
    step = values.size > 1 ? width.to_f / (values.size - 1) : 0
    placed = values.each_with_index.map { |value, index| "#{(index * step).round(1)},#{(height - 2 - (value - low) / span * (height - 4)).round(1)}" unless value.nil? }
    runs = placed.slice_when { |before, after| before.nil? != after.nil? }.reject { |run| run.first.nil? }
    end_x, end_y = placed.compact.last.split(",")
    tag.svg(
      viewBox: "0 0 #{width} #{height}",
      preserveAspectRatio: "none",
      role: "img",
      aria: {label: label},
      class: "h-6 w-20 overflow-visible text-slate-500",
      data: {reveal: "left"}
    ) do
      safe_join([
        tag.title(label),
        *runs.map do |run|
          next sparkline_dot(*run.first.split(","), 3) if run.size == 1

          tag.polyline(
            points: run.join(" "),
            fill: "none",
            stroke: "currentColor",
            "stroke-width": 1.5,
            "stroke-linejoin": "round",
            "vector-effect": "non-scaling-stroke"
          )
        end,
        # A zero-length round-capped line, since a circle would be squashed
        # by the stretch to the box.
        sparkline_dot(end_x, end_y, 5)
      ])
    end
  end

  def sparkline_dot(x, y, size)
    tag.line(x1: x, y1: y, x2: x, y2: y, stroke: "currentColor", "stroke-width": size, "stroke-linecap": "round", "vector-effect": "non-scaling-stroke")
  end

  # Both styles start at zero so heights compare honestly. A unit that is a
  # whole word is dropped so it doesn't repeat the label beside the figure.
  def reading_unit(unit)
    unit.to_s.match?(/\A\s*[[:alpha:]]{4,}\s*\z/) ? "" : unit.to_s
  end

  def time_chart(points, label:, y_title:, x_title: nil, style: :bars, unit: "", per: :day, events: {}, event_name: nil, unsettled: nil, legend: nil, previous: nil, previous_name: nil, zoom: true)
    unit = reading_unit(unit)
    skip = leading_empty(points.map(&:first), [points.map(&:last), previous].compact)
    points, previous = points.drop(skip), previous&.drop(skip)
    keys = points.map(&:first)
    if style == :line
      return line_chart(keys, [Series.new(name: label, values: points.map(&:last))], label: label, unit: unit, y_title: y_title, x_title: x_title,
        events: events, event_name: event_name, unsettled: unsettled)
    end

    events = events.slice(*keys)
    safe_join([
      (swatch_legend([[legend, BAR_COLOR]], dotted: (previous_name if previous)) if legend || previous),
      (event_legend(event_name) if events.any?),
      chart_frame(keys, [*points.map(&:last), *previous].compact.max, label, x_title: x_title, y_title: y_title, per: per, zoom: zoom,
        overlay: (->(_) { event_markers(keys, events, lines: false) } if events.any?)) do |max|
        safe_join([
          bar_marks(points, max, unit, per, events, event_name, unsettled: unsettled, previous: previous, previous_name: previous_name, metric: y_title, zoom: zoom),
          (previous_bars_line(keys, previous, max) if previous)
        ].compact)
      end
    ].compact)
  end

  # The rest grouped as :other always takes the grey, so it reads as left
  # over rather than as one more group.
  def share_series(groups)
    groups.each_with_index.map do |(key, values), index|
      other = key == :other
      Series.new(name: other ? "Other" : yield(key), values: values, color: other ? SHARE_OTHER_COLOR : SHARE_COLORS[index])
    end
  end

  # The first part sits at the base so its height can be read straight off
  # the axis. A line gets its own scale because its figures differ in size
  # from the bars'. A part below zero can't be stacked, so it is left undrawn
  # and only read out; total_name adds each bar's sum to the readout, so a stack's height can be read as a figure.
  def stacked_chart(keys, series, label:, y_title:, x_title: nil, per: :day, titles: nil, unsettled: nil, previous: nil, previous_name: nil, line: nil, total_name: nil)
    skip = leading_empty(keys, [*[*series, line].compact.map(&:values), previous].compact)
    keys, series, titles, previous = keys.drop(skip), trimmed_series(series, skip), titles&.drop(skip), previous&.drop(skip)
    line = line.dup.tap { |copy| copy.values = line.values.drop(skip) } if line && skip.positive?
    totals = keys.each_index.map { |index| series.sum { |part| [part.values[index].to_i, 0].max } }
    top = round_top([*totals, *previous&.compact].max.to_f, whole: true)
    line_top = round_top(line.values.compact.max.to_f, whole: line.whole) if line
    safe_join([
      swatch_legend([*series.map { |part| [part.name, part.color] }, *([[line.name, line.color, true]] if line)], dotted: (previous_name if previous)),
      chart_frame(keys, top, label, x_title: x_title, y_title: y_title, per: per, left: series.any?,
        right: (measure_axis(line, line_top, side: :right, outer: false, tall: false) if line)) do |max|
        safe_join([
          stacked_marks(keys, series, max, per, titles, unsettled: unsettled, previous: previous, previous_name: previous_name, line: line, line_top: line_top,
            total_name: total_name),
          (previous_bars_line(keys, previous, max) if previous),
          (measure_line(keys, line, line_top) if line)
        ].compact)
      end
    ])
  end

  # Drawn over the bars it shares a chart with, in runs so a day without
  # data is a gap rather than a drop to zero.
  def measure_line(keys, measure, top)
    max = [top.to_f, 1].max
    safe_join(line_runs(measure.values).map do |run|
      points = run.map { |value, index| "#{point_x(index, keys.size)},#{((1 - value.to_f / max) * CHART_HEIGHT).round(2)}" }.join(" ")
      tag.polyline(points: points, fill: "none", stroke: measure.color, "stroke-width": 2, "stroke-linejoin": "round",
        "vector-effect": "non-scaling-stroke", class: "pointer-events-none")
    end)
  end

  # One shared axis so series are only ever compared in the same unit.
  def line_chart(keys, series, label:, y_title:, x_title: nil, unit: "", selectable: false, per: :day, events: {}, event_name: nil, unsettled: nil)
    unit = reading_unit(unit)
    skip = leading_empty(keys, series.map(&:values))
    keys, series = keys.drop(skip), trimmed_series(series, skip)
    max = series.flat_map(&:values).compact.max
    events = events.slice(*keys)
    safe_join([
      (chart_legend(series, selectable: selectable, events: (event_name if events.any?)) if series.size > 1 || events.any?),
      chart_frame(keys, max, label, x_title: x_title, y_title: y_title, crosshair: true, lines: true, per: per,
        overlay: ->(top) { safe_join([line_end_markers(keys, series, top), event_markers(keys, events)]) }) do |top|
        line_marks(keys, series, top, unit, per, events, event_name, unsettled: unsettled, y_title: y_title)
      end
    ].compact)
  end

  # An axis per figure in its line's colour, so a line is read against the
  # scale it was drawn on. Past two, the outer axes give way on
  # a phone, which has no room for four; the readout still has every figure.
  def measures_chart(keys, measures, label:, per: :day, unsettled: nil)
    skip = leading_empty(keys, measures.flat_map { |measure| [measure.values, measure.previous].compact })
    if skip.positive?
      keys = keys.drop(skip)
      measures = measures.map { |measure| measure.dup.tap { |copy| copy.values, copy.previous = measure.values.drop(skip), measure.previous&.drop(skip) } }
    end
    x = ->(index) { point_x(index, keys.size) }
    tops = measures.map { |measure| round_top([*measure.values, *measure.previous].compact.max.to_f, whole: measure.whole) }
    ys = measures.zip(tops).map do |measure, top|
      ->(value) { ((measure.inverted ? value.to_f / top : 1 - value.to_f / top) * CHART_HEIGHT).round(2) }
    end
    lines = measures.each_with_index.flat_map do |measure, index|
      line_runs(measure.values).map do |run|
        tag.polyline(points: run.map { |value, i| "#{x.(i)},#{ys[index].(value)}" }.join(" "), fill: "none", stroke: measure.color,
          "stroke-width": 2, "stroke-linejoin": "round", "stroke-dasharray": ("4 3" if measure.dashed), "vector-effect": "non-scaling-stroke",
          class: "pointer-events-none")
      end
    end
    previous_lines = measures.each_with_index.flat_map do |measure, index|
      line_runs(measure.previous || []).map do |run|
        tag.polyline(points: run.map { |value, i| "#{x.(i)},#{ys[index].(value)}" }.join(" "), fill: "none", stroke: measure.color,
          "stroke-width": 2, "stroke-linejoin": "round", "stroke-linecap": "round", "stroke-dasharray": "0 4", "stroke-opacity": 0.6,
          "vector-effect": "non-scaling-stroke", class: "pointer-events-none", data: {previous: ""})
      end
    end
    earlier = previous_chart_keys(keys, per)
    # A figure with nothing to compare still says its day, since the readout
    # is headed by a place in the period rather than a date.
    chart_compared = measures.any? { |measure| measure.previous.present? }
    hits = keys.each_with_index.map do |key, index|
      rows = measures.each_with_index.flat_map do |measure, measure_index|
        value = measure.values[index]
        compared = measure.previous.present?
        current = {
          value: value.nil? ? "No data" : measure.reading.(value),
          **compared_name(measure.name, key, per, chart_compared),
          color: measure.color,
          dashed: (true if measure.dashed),
          y: (ys[measure_index].(value) unless value.nil?)
        }.compact
        next [current] unless compared

        before = measure.previous[index]
        current.merge!(change: compare_change(value, before), tone: (value <=> before if value && before)) unless value.nil? || before.nil?
        [current, {value: before.nil? ? "No data" : measure.reading.(before), **compared_name(measure.name, earlier&.at(index), per, true, measure.previous_name),
                   color: measure.color, dotted: true, earlier: true, y: (ys[measure_index].(before) unless before.nil?)}.compact]
      end
      tag.rect(
        y: 0,
        height: CHART_HEIGHT,
        fill: "transparent",
        data: chart_tip(time_tip_title(key, per, index, chart_compared), rows, x: x.(index), note: unsettled_note(key, per, unsettled), key: zoom_key(key, per)),
        **point_hit(index, keys.size)
      )
    end
    markers = measures.each_with_index.flat_map do |measure, index|
      known = measure.values.each_index.reject { |i| measure.values[i].nil? }
      [known.first, known.last].compact.uniq.map do |i|
        tag.span(class: "pointer-events-none absolute size-2 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2 ring-white",
          style: "left: #{(x.(i) / CHART_WIDTH * 100).round(2)}%; top: #{(ys[index].(measure.values[i]) / CHART_HEIGHT * 100).round(2)}%; " \
            "background-color: #{measure.color}", aria: {hidden: true})
      end
    end
    axes = measures.zip(tops).each_with_index.map do |(measure, top), index|
      measure_axis(measure, top, side: index.even? ? :left : :right, outer: index > 1)
    end

    tag.figure(class: "min-w-0") do
      chart_tooltip(label: label, crosshair: true, class: "grid grid-cols-[auto_minmax(0,1fr)_auto]") do
        safe_join([
          tag.div(class: "flex") { safe_join(axes.values_at(2, 0).compact) },
          tag.div(class: ["relative min-w-0", zoom_cursor(keys, per)]) do
            safe_join([
              tag.svg(viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", preserveAspectRatio: "none", role: "img", aria: {label: label},
                class: "block h-56 w-full overflow-visible", data: {reveal: "left"}) { safe_join([grid_lines, *previous_lines, *lines.reverse, *hits]) },
              *markers
            ])
          end,
          tag.div(class: "flex") { safe_join(axes.values_at(1, 3).compact) },
          tag.span, x_axis(keys, format: DATE_AXIS_FORMATS[per], inset: nil, lines: true, per: per), tag.span,
          tag.span, axis_title(DATE_AXIS_TITLES.fetch(per), class: "text-center"), tag.span
        ])
      end
    end
  end

  # Bars across rather than up, so long names stay readable. The readout
  # repeats the name in full because a touch screen never shows a title.
  # Round gridlines so a bar's length can be read off the axis as well as
  # from its figure.
  def ranking_chart(rows, label:, total:, x_title:, y_title:, first_series: nil, previous: nil, previous_name: nil, changes: {}, links: {})
    step, top = axis_scale(rows.map { |_, value, _| value.to_f }.max.to_f)
    ticks = (0..(top / step).round).map { |index| index * step }
    columns = "grid grid-cols-[minmax(0,11rem)_1fr] gap-x-3"
    tag.figure(class: "flex min-w-0 flex-1 flex-col") do
      safe_join([
        tag.div(class: [columns, "mb-1 px-1"], aria: {hidden: true}) { safe_join([axis_title(y_title, class: "truncate text-left"), tag.span]) },
        chart_tooltip(label: label, class: "flex flex-1 flex-col") do
          tag.ul(class: "grid flex-1 auto-rows-fr text-xs") do
            safe_join(rows.each_with_index.map do |(name, value, swatch, color, marker), index|
              share = share_of_total(value, total)
              readings = if previous
                compared_readings(x_title, number_with_delimiter(value), number_with_delimiter(previous[name].to_i), previous_name,
                  color: color, current_value: value, before_value: previous[name].to_i)
              else
                [{value: number_with_delimiter(value), name: x_title, color: color, marker: marker}.compact]
              end
              readings << {value: share, name: "Share of total"} if share
              tip = chart_tip(name, readings)
              tip = tip.merge(series: first_series + index) if first_series
              tag.li(class: [columns, "min-h-8 rounded px-1 transition-opacity has-data-active:bg-slate-100", ("cursor-pointer" if first_series)],
                data: ({action: "click->series-highlight#toggle"} if first_series)) do
                safe_join([
                  tag.span(class: "flex min-w-0 flex-wrap items-center gap-x-1 self-center", data: ({series: first_series + index} if first_series)) do
                    safe_join([chart_row_name(name, links[name]), changes[name]].compact, " ")
                  end,
                  tag.div(class: "relative flex items-center py-1", data: tip.merge(reveal: "left")) do
                    safe_join([
                      *ticks.drop(1).map do |tick|
                        tag.span(class: "absolute inset-y-0 w-px bg-slate-200", style: "left: #{(tick / top * 100).round(2)}%", aria: {hidden: true})
                      end,
                      tag.span(class: "absolute inset-y-0 left-0 w-px bg-slate-300", aria: {hidden: true}),
                      tag.span(class: "absolute top-1/2 -left-1.5 h-px w-1.5 bg-slate-300", aria: {hidden: true}),
                      tag.div(class: ["relative h-5 shrink-0 rounded-r-sm", swatch], style: "width: #{(value.to_f / top * 100).round(2)}%")
                    ])
                  end
                ], " ")
              end
            end)
          end
        end,
        tag.div(class: [columns, "mt-1 px-1 text-xs text-slate-400"], aria: {hidden: true}) do
          safe_join([
            tag.span,
            tag.div(class: "relative h-4") do
              safe_join(ticks.map do |tick|
                tag.span(compact_number(tick), style: "left: #{(tick / top * 100).round(2)}%", class: "absolute top-0 -translate-x-1/2 tabular-nums")
              end)
            end
          ])
        end,
        tag.div(class: [columns, "px-1"], aria: {hidden: true}) { safe_join([tag.span, axis_title(x_title, class: "text-center")]) }
      ])
    end
  end

  # Joined so the gap between the two figures is what's read rather than
  # either alone; shaped as well as coloured so they're told apart without
  # hue. A fixed scale, since a score out of 100 means the same whatever the
  # highest one is.
  def dumbbell_chart(rows, keys:, label:, x_title:, y_title:, top: 100, ticks: [0, 25, 50, 75, 100], links: {})
    columns = "grid grid-cols-[minmax(0,1fr)_minmax(0,2fr)] gap-x-3 sm:grid-cols-[minmax(0,11rem)_1fr]"
    left = ->(value) { (value.to_f / top * 100).clamp(0, 100).round(2) }
    tag.figure(class: "min-w-0") do
      safe_join([
        tag.ul(class: "mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600") do
          safe_join(keys.map do |name, color, marker|
            tag.li(class: "inline-flex items-center gap-1.5") { safe_join([marker_svg(marker, color, size: 10), name]) }
          end)
        end,
        tag.div(class: [columns, "mb-1 px-1"], aria: {hidden: true}) { safe_join([axis_title(y_title, class: "truncate text-left"), tag.span]) },
        chart_tooltip(label: label) do
          tag.ul(class: "grid text-xs") do
            safe_join(rows.map do |name, values|
              known = values.compact
              readings = keys.zip(values).map do |(key, color, marker), value|
                {value: value.nil? ? "No data" : number_with_delimiter(value.round), name: key, color: color, marker: marker}
              end
              readings << {value: number_with_delimiter((known.max - known.min).round), name: "Gap", color: "#94a3b8"} if known.size > 1
              # On the track alone, so the name and the axis don't open the readout.
              tag.li(class: [columns, "min-h-8 rounded px-1 has-data-active:bg-slate-100"]) do
                safe_join([
                  chart_row_name(name, links[name], class: "self-center"),
                  tag.div(class: "relative h-8", data: chart_tip(name, readings)) do
                    safe_join([
                      *ticks.map { |tick| tag.span(class: "absolute inset-y-0 w-px bg-slate-200", style: "left: #{left.(tick)}%", aria: {hidden: true}) },
                      (if known.size > 1
                         tag.span(class: "absolute top-1/2 h-0.5 -translate-y-1/2 bg-slate-400",
                           style: "left: #{left.(known.min)}%; width: #{(left.(known.max) - left.(known.min)).round(2)}%", aria: {hidden: true})
                       end),
                      *keys.zip(values).filter_map do |(_, color, marker), value|
                        next if value.nil?

                        tag.span(marker_svg(marker, color, size: 10, outline: true), style: "left: #{left.(value)}%", aria: {hidden: true},
                          class: "pointer-events-none absolute top-1/2 flex -translate-x-1/2 -translate-y-1/2")
                      end
                    ].compact)
                  end
                ], " ")
              end
            end)
          end
        end,
        tag.div(class: [columns, "mt-1 px-1 text-xs text-slate-400"], aria: {hidden: true}) do
          safe_join([
            tag.span,
            tag.div(class: "relative h-4") do
              safe_join(ticks.map { |tick| tag.span(compact_number(tick), style: "left: #{left.(tick)}%", class: "absolute top-0 -translate-x-1/2 tabular-nums") })
            end
          ])
        end,
        tag.div(class: [columns, "px-1"], aria: {hidden: true}) { safe_join([tag.span, axis_title(x_title, class: "text-center")]) }
      ])
    end
  end

  # Against a dashed curve of what's usual so a row far off it stands out.
  # The points sit over the SVG rather than in it, so they stay round however
  # wide the chart is drawn. y_min keeps a measure that falls below zero on
  # the chart, and lines mark levels such as a median the points are read against.
  def scatter_chart(points, label:, x_title:, y_title:, x_max:, x_ticks:, y_tick:, curve: [], key: [], x_min: 1, x_tick: ->(tick) { tick },
    y_min: 0, y_max: nil, lines: [])
    y_top = y_max || round_top([*points.map(&:y), *curve.map(&:last)].compact.max.to_f)
    y_span = y_top - y_min
    left = ->(x) { ((x.to_f - x_min) / (x_max - x_min) * 100).clamp(0, 100).round(2) }
    top = ->(y) { (100 - (y.to_f - y_min) / y_span * 100).clamp(0, 100).round(2) }
    line = if curve.size > 1
      tag.polyline(points: curve.map { |x, y| "#{(left.(x) * CHART_WIDTH / 100).round(2)},#{(top.(y) * CHART_HEIGHT / 100).round(2)}" }.join(" "),
        fill: "none", stroke: LINE_COLORS.first, "stroke-width": 2, "stroke-dasharray": "4 3", "vector-effect": "non-scaling-stroke",
        class: "pointer-events-none")
    end
    levels = lines.map do |level|
      y = (top.(level[:y]) * CHART_HEIGHT / 100).round(2)
      tag.line(x1: 0, x2: CHART_WIDTH, y1: y, y2: y, stroke: level[:color] || LINE_COLORS.first, "stroke-width": level[:width] || 2,
        "stroke-dasharray": ("4 3" if level[:dashed]), "vector-effect": "non-scaling-stroke", class: "pointer-events-none")
    end
    dots = points.map do |point|
      # Matched to its key by colour, so a point needs no series of its own.
      series = key.index { |_, color| color == point.color }
      tag.span(class: "absolute size-2.5 -translate-x-1/2 -translate-y-1/2 rounded-full ring-1 ring-white transition-opacity hover:ring-2 hover:ring-slate-900 " \
        "data-active:z-10 data-active:ring-2 data-active:ring-slate-900",
        style: "left: #{left.(point.x)}%; top: #{top.(point.y)}%; background-color: #{point.color}", data: point.tip.merge({series: series}.compact))
    end
    tag.figure(class: "min-w-0", data: ({controller: "series-highlight"} if key.any?)) do
      safe_join([
        (swatch_legend(key, selectable: true) if key.any?),
        chart_tooltip(label: label) do
          tag.div(class: "flex") do
            safe_join([
              y_axis_title(y_title, tall: true),
              y_axis([y_tick.(y_top), y_tick.(y_min + y_span / 2.0), y_tick.(y_min)], tall: true),
              tag.div(class: "relative min-w-0 flex-1") do
                safe_join([
                  tag.svg(viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", preserveAspectRatio: "none", role: "img", aria: {label: label},
                    class: "block h-56 w-full overflow-visible", data: {reveal: "fade"}) { safe_join([grid_lines, *levels, line].compact) },
                  *dots
                ])
              end
            ])
          end
        end,
        tag.div(class: "relative ml-14 h-5.5 border-t border-slate-300 text-xs text-slate-400", aria: {hidden: true}) do
          safe_join(x_ticks.flat_map do |tick|
            [tag.span(x_tick.(tick), style: "left: #{left.(tick)}%", class: ["absolute top-1.5 whitespace-nowrap tabular-nums", ("-translate-x-1/2" unless tick == x_min)]),
             tag.span(class: "absolute top-0 h-1 w-px bg-slate-300", style: "left: #{left.(tick)}%")]
          end)
        end,
        axis_title(x_title, class: "ml-14 text-center")
      ].compact)
    end
  end

  # Log-scaled because a few cells hold most of the views, and a linear
  # scale would leave the rest the same pale shade.
  def heat_class(value, max)
    return "bg-white text-slate-300" if value.to_f.zero?

    HEAT_CLASSES[[(Math.log(value + 1) / Math.log(max + 1) * (HEAT_CLASSES.size - 1)).round, HEAT_CLASSES.size - 1].min]
  end

  # Apart from chart_frame so a heatmap or a strip of days gets the same
  # readout as a chart. touch-pan-y so vertical swipes still scroll the page
  # while sideways ones read across the days.
  def chart_tooltip(label:, crosshair: false, **options, &block)
    tag.div(class: ["group/chart relative touch-pan-y touch-pinch-zoom rounded focus-visible:outline-2 focus-visible:outline-offset-4 focus-visible:outline-slate-400",
      options[:class]],
      tabindex: 0, role: "group", aria: {label: "#{label}. Arrow keys read each value."},
      data: {controller: "chart-tooltip",
             action: "pointerdown->chart-tooltip#point pointermove->chart-tooltip#point pointerleave->chart-tooltip#leave pointercancel->chart-tooltip#cancel " \
               "focus->chart-tooltip#focus blur->chart-tooltip#hide keydown->chart-tooltip#key"}) do
      safe_join([
        capture(&block),
        (tag.span(hidden: true, class: "pointer-events-none absolute w-px bg-slate-400", data: {chart_tooltip_target: "crosshair"}) if crosshair),
        tag.div(hidden: true, role: "status",
          class: "pointer-events-none fixed z-50 max-w-xs rounded-md border border-slate-200 bg-white px-3 py-2 text-xs shadow-lg",
          data: {chart_tooltip_target: "tooltip"})
      ].compact)
    end
  end

  # JSON so names reach the page as text, never as markup.
  def chart_tip(title, rows, x: nil, note: nil, key: nil, href: nil)
    # The figures read together, then what each was in the period compared
    # with, whichever order a chart builds them in.
    rows = rows.partition { |row| !row[:earlier] }.flatten(1)
    {chart_tooltip_target: "hit", tip: {title: title, rows: rows, x: x, note: note, key: key, href: href}.compact.to_json}
  end

  # Only a day can become a period to zoom to, since a week or month would
  # need a bucket's end the chart doesn't carry.
  def zoom_key(key, per)
    key.to_date.iso8601 if @period && per.to_s == "day" && key.respond_to?(:strftime)
  end

  # The crosshair promises a drag to zoom, so a chart that can't be zoomed
  # keeps the plain pointer.
  def zoom_cursor(keys, per)
    "cursor-crosshair" if keys.first && zoom_key(keys.first, per)
  end

  # Buttons as well as gestures, since a wheel or pinch can't be found by
  # someone who doesn't know it is there.
  def map_zoom_buttons
    button = "grid size-8 place-items-center rounded border border-slate-200 bg-white/90 text-slate-700 shadow-sm " \
      "hover:bg-slate-50 focus-visible:outline-2 focus-visible:outline-slate-400 disabled:cursor-default disabled:text-slate-300 disabled:hover:bg-white/90"
    tag.div(class: "absolute top-2 right-2 flex flex-col gap-1", data: {map_zoom_control: ""}) do
      safe_join([
        tag.button(icon("plus"), type: "button", class: button, aria: {label: "Zoom in"}, data: {action: "map-zoom#in", map_zoom_target: "in"}),
        tag.button(icon("minus"), type: "button", class: button, aria: {label: "Zoom out"}, data: {action: "map-zoom#out", map_zoom_target: "out"}, disabled: true)
      ])
    end
  end

  # A log scale, since a few countries hold most of the traffic and a linear
  # one would leave every other country the same pale shade.
  def world_map(counts, label:, unit:, previous: nil, previous_name: nil, links: {}, details: {}, also: [])
    max = counts.values.max.to_i
    off_map = counts.reject { |code, count| WorldMap.codes.include?(code) || code == GoogleReportsHelper::UNKNOWN_COUNTRY || count.zero? }
    tag.figure(class: "min-w-0") do
      safe_join([
        chart_tooltip(label: label) do
          tag.div(class: "relative touch-pan-y", data: {controller: "map-zoom", action: "pointerdown->map-zoom#grab pointermove->map-zoom#drag pointerup->map-zoom#release pointercancel->map-zoom#release wheel->map-zoom#wheel:!passive dblclick->map-zoom#double"}) do
          safe_join([tag.svg(viewBox: "0 0 #{WorldMap.width} #{WorldMap.height}", width: WorldMap.width, height: WorldMap.height,
            role: "img", aria: {label: label}, class: "h-auto w-full", data: {map_zoom_target: "svg"}) do
            safe_join(WorldMap.countries.map do |country|
              count = counts.fetch(country.code, 0)
              rows = [{value: number_with_delimiter(count), name: unit.pluralize(count).upcase_first}]
              outline = "stroke-white"
              width = 0.5
              if previous
                before = previous.fetch(country.code, 0)
                rows = compared_readings(unit.pluralize.upcase_first, number_with_delimiter(count), number_with_delimiter(before), previous_name,
                  current_value: count, before_value: before)
                outline, width = map_outline(count, before)
              end
              rows += also.flat_map { |name, others, earlier| map_reading(name, others.fetch(country.code, 0), earlier&.fetch(country.code, 0), previous_name) }
              rows += details[country.code].to_a.map { |name, value| {value: number_with_delimiter(value), name: name} }
              tag.path(d: country.path, class: [map_fill(count, max), outline, "hover:opacity-75 data-active:opacity-75"], "stroke-width": width,
                # Busiest first, on the same scale as the fill, so the map fills in from where the traffic is.
                style: "animation-delay: #{map_reveal_delay(count, max)}ms",
                data: chart_tip("#{country_flag(country.code)} #{country.name}", rows, href: links[country.code]).merge(reveal: "fade"))
            end)
          end, map_zoom_buttons])
          end
        end,
        map_legend(max, unit, compared: previous.present?),
        (tag.figcaption(class: "mt-1 text-xs text-slate-500") do
          "Too small for the map: " + off_map.sort_by { |code, count| [-count, code] }
            .map { |code, count| "#{country_label(code)} #{number_with_delimiter(count)}" }.join(", ")
        end if off_map.any?)
      ].compact)
    end
  end

  # Shares rather than counts, so a drift in the audience shows as segments
  # growing or shrinking; inset by a gap so touching colours stay apart.
  def share_chart(shares, label:, y_title:, key_label: ->(key) { country_label(key) }, count_name: "view", empty: "No views in this period.")
    named = shares[:keys]
    buckets = shares[:buckets]
    return tag.p(empty, class: "text-sm text-slate-500") if buckets.empty?

    keys = [[:other, SHARE_OTHER_FILL, SHARE_OTHER_COLOR], *named.zip(SHARE_FILLS, SHARE_COLORS)]
    slot = CHART_WIDTH.to_f / buckets.size
    bars = buckets.each_with_index.map do |(start, counts), index|
      total = counts.values.sum.to_f
      y = CHART_HEIGHT.to_f
      segments = keys.filter_map do |key, fill, _|
        height = total.zero? ? 0 : counts.fetch(key, 0) / total * CHART_HEIGHT
        y -= height
        next if height.zero?

        tag.rect(x: (index * slot + 2).round(2), y: y.round(2), width: [slot - 4, 1].max.round(2), height: height.round(2),
          class: [fill, "stroke-white"], "stroke-width": 2, "vector-effect": "non-scaling-stroke")
      end
      # Other last so the readout lists countries in the legend's order.
      rows = keys.rotate.map do |key, _, color|
        count = counts.fetch(key, 0)
        {value: total.zero? ? "—" : "#{number_to_percentage(count / total * 100, precision: 1)} · #{number_with_delimiter(count)}",
         color: color, name: key == :other ? "Other" : key_label.(key)}
      end
      hit = tag.rect(x: (index * slot).round(2), y: 0, width: slot.round(2), height: CHART_HEIGHT, fill: "transparent",
        class: "hover:stroke-slate-900 data-active:stroke-slate-900", "stroke-width": 2, "vector-effect": "non-scaling-stroke",
        data: chart_tip(chart_point_label(start, shares[:unit]), rows))
      safe_join([*segments, hit])
    end
    tag.figure(class: "min-w-0") do
      safe_join([
        share_legend(named, key_label),
        chart_tooltip(label: label) do
          tag.div(class: "flex") do
            safe_join([
              y_axis_title(y_title),
              y_axis(%w[100% 50% 0%]),
              tag.svg(viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", preserveAspectRatio: "none", role: "img", aria: {label: label},
                class: "h-32 min-w-0 flex-1", data: {reveal: "up"}) { safe_join(bars) }
            ])
          end
        end,
        x_axis(buckets.keys, format: shares[:unit] == :month ? "%b %Y" : nil),
        axis_title(DATE_AXIS_TITLES.fetch(shares[:unit]), class: "ml-14 text-center")
      ])
    end
  end

  def share_bucket_label(start, unit)
    unit == :week ? l(start) : l(start, format: "%B %Y")
  end

  # A donut is judged at a glance, so the rest fold into Other, and the key
  # beside it gives every count and share so no figure rests on judging an
  # angle. Slices are cut short of each other so touching colours stay apart.
  def donut_chart(counts, label:, unit:, empty:)
    rows = counts.map { |key, count| [key.to_s, count.to_i] }.reject { |_, count| count.zero? }.sort_by { |key, count| [-count, key] }
    return tag.p(empty, class: "text-sm text-slate-500") if rows.empty?

    shown = rows.size > DONUT_SLICES ? rows.first(DONUT_SLICES - 1) : rows
    rest = rows.drop(shown.size)
    slices = shown.zip(SHARE_COLORS, SHARE_SWATCHES).map { |(name, count), color, swatch| [name, count, color, swatch] }
    slices << ["Other", rest.sum(&:last), SHARE_OTHER_COLOR, SHARE_OTHER_SWATCH] if rest.any?
    total = rows.sum(&:last).to_f
    share = ->(count) { number_to_percentage(count / total * 100, precision: 1) }
    radius = 40
    point = ->(turn) { [(50 + radius * Math.sin(turn * 2 * Math::PI)).round(3), (50 - radius * Math.cos(turn * 2 * Math::PI)).round(3)] }
    gap = slices.size > 1 ? 0.004 : 0
    start = 0.0
    arcs = slices.each_with_index.map do |(name, count, color, _), index|
      turn = count / total
      readings = [{value: number_with_delimiter(count), name: unit.pluralize(count).upcase_first, color: color}, {value: share.(count), name: "Share"}]
      readings += rest.map { |key, held| {value: number_with_delimiter(held), name: key} } if name == "Other"
      data = chart_tip(name, readings).merge(series: index, series_arc: "")
      mark = if slices.size == 1
        tag.circle(cx: 50, cy: 50, r: radius, data: data, **donut_stroke(color))
      else
        inset = [gap, turn / 4].min
        (x0, y0), (x1, y1) = point.(start + inset), point.(start + turn - inset)
        tag.path(d: "M#{x0} #{y0}A#{radius} #{radius} 0 #{turn - 2 * inset > 0.5 ? 1 : 0} 1 #{x1} #{y1}", data: data, **donut_stroke(color))
      end
      start += turn
      mark
    end
    tag.figure(class: "flex min-w-0 flex-wrap items-center gap-x-6 gap-y-4", data: {controller: "series-highlight"}) do
      safe_join([
        chart_tooltip(label: label, class: "relative mx-auto size-36 shrink-0") do
          safe_join([
            tag.svg(viewBox: "0 0 100 100", role: "img", aria: {label: label}, class: "size-36", data: {reveal: "circle"}) { safe_join(arcs) },
            tag.div(class: "pointer-events-none absolute inset-0 flex flex-col items-center justify-center", aria: {hidden: true}) do
              safe_join([
                tag.span(compact_number(total), class: "text-lg font-semibold text-slate-900 tabular-nums"),
                tag.span(unit.pluralize(total), class: "text-xs text-slate-500")
              ])
            end
          ])
        end,
        tag.ul(class: "min-w-48 flex-1 space-y-1.5 text-sm") do
          safe_join(slices.each_with_index.map do |(name, count, _, swatch), index|
            tag.li(class: "flex items-center gap-2", data: {series: index, action: "mouseenter->series-highlight#preview mouseleave->series-highlight#restore"}) do
              safe_join([
                tag.span(class: "size-2.5 shrink-0 rounded-sm #{swatch}", aria: {hidden: true}),
                tag.span(name, class: "min-w-0 flex-1 truncate font-medium text-slate-700"),
                tag.span(number_with_delimiter(count), class: "tabular-nums text-slate-600"),
                tag.span(share.(count), class: "w-14 shrink-0 text-right tabular-nums text-slate-900")
              ], " ")
            end
          end)
        end
      ])
    end
  end

  # Over a pale bar as wide as the step before, so what was lost is the bare
  # part either side. Steps are counted apart and one can exceed the one
  # before, so only a loss is marked.
  def funnel_chart(steps, label:, unit:, previous: nil, previous_name: nil)
    first = steps.first&.last.to_i
    width = ->(count) { first.zero? ? 0 : (count.to_f / first * 100).clamp(0, 100).round(2) }
    chart_tooltip(label: label) do
      tag.ol(class: "space-y-1 text-sm") do
        safe_join(steps.each_with_index.map do |(name, count), index|
          before = steps[index - 1].last if index.positive?
          lost = before - count if before && count < before
          earlier = previous[index].last if previous
          readings = if previous
            compared_readings(unit.pluralize(count).upcase_first, number_with_delimiter(count), number_with_delimiter(earlier), previous_name,
              color: BAR_COLOR, current_value: count, before_value: earlier)
          else
            [{value: number_with_delimiter(count), name: unit.pluralize(count).upcase_first, color: BAR_COLOR}]
          end
          readings << {value: number_to_percentage(width.(count), precision: 0), name: "Share of #{steps.first.first.downcase}"} if index.positive?
          readings << {value: "−#{number_with_delimiter(lost)}", name: "Lost since #{steps[index - 1].first.downcase}"} if lost
          tag.li(class: "grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)_auto] items-center sm:grid-cols-[minmax(0,9rem)_1fr_5.5rem] gap-3 rounded px-1 has-data-active:bg-slate-100") do
            safe_join([
              tag.span(name, class: "truncate font-medium"),
              tag.div(class: "relative flex h-6 justify-center", data: chart_tip(name, readings).merge(reveal: "left")) do
                safe_join([
                  (tag.span(class: "absolute inset-y-0 left-1/2 -translate-x-1/2 rounded-sm bg-slate-200", style: "width: #{width.(before)}%") if lost),
                  tag.span(class: "relative h-full rounded-sm bg-slate-600", style: "width: #{width.(count)}%")
                ].compact)
              end,
              tag.span(class: "text-right tabular-nums") do
                safe_join([
                  number_with_delimiter(count),
                  (tag.span(" −#{number_to_percentage(lost * 100.0 / before, precision: 0)}", class: "text-xs text-red-700") if lost),
                  (row_change(count, earlier, CompareHelper::MORE_IS_BETTER) if previous)
                ].compact)
              end
            ], " ")
          end
        end)
      end
    end
  end

  # Each row's whole along one bar, so rows of different sizes compare by
  # share; the parts sit a surface gap apart so neighbours stay told apart.
  # The readout gives each part's count, since the bar shows only shares.
  def split_bars(rows, parts:, label:, unit:, links: {})
    columns = "grid grid-cols-[minmax(0,1fr)_minmax(0,1.5fr)] gap-x-3 sm:grid-cols-[minmax(0,14rem)_1fr]"
    tag.figure(class: "min-w-0") do
      safe_join([
        swatch_legend(parts),
        chart_tooltip(label: label) do
          tag.ul(class: "grid text-xs") do
            safe_join(rows.map do |name, counts|
              total = counts.sum.to_f
              readings = parts.zip(counts).map do |(part, color), count|
                {value: total.zero? ? "—" : "#{number_to_percentage(count / total * 100, precision: 1)} · #{number_with_delimiter(count)}",
                 name: part, color: color}
              end
              # On the bar alone, so the name and the axis don't open the readout.
              tag.li(class: [columns, "min-h-8 rounded px-1 has-data-active:bg-slate-100"]) do
                safe_join([
                  chart_row_name(name, links[name], class: "self-center"),
                  tag.div(class: "flex h-5 gap-0.5 self-center overflow-hidden rounded-sm", aria: {hidden: true},
                    data: chart_tip(name, readings).merge(total.zero? ? {} : {reveal: "left"})) do
                    next tag.span("None yet", class: "text-slate-400") if total.zero?

                    safe_join(parts.zip(counts).filter_map do |(_, color), count|
                      tag.span(style: "width: #{(count / total * 100).round(2)}%; background-color: #{color}") if count.positive?
                    end)
                  end
                ])
              end
            end)
          end
        end,
        tag.div(class: [columns, "mt-1 px-1 text-xs text-slate-400"], aria: {hidden: true}) do
          safe_join([tag.span, tag.div(class: "flex justify-between tabular-nums") { safe_join(%w[0% 50% 100%].map { |tick| tag.span(tick) }) }])
        end
      ])
    end
  end

  # A day with nothing can take its own shade, so white doesn't read as a gap
  # in a calendar.
  def heat_cell(text, value, max, tip:, empty: nil, rounded: "rounded", **options)
    shade = empty && value.to_f.zero? ? empty : heat_class(value, max)
    tag.div(text, class: [rounded, "px-1 py-1 text-center tabular-nums hover:ring-2 hover:ring-slate-900 data-active:ring-2 data-active:ring-slate-900",
      shade, options[:class]], data: tip)
  end

  def share_bar(parts, label:, height: "h-3")
    chart_tooltip(label: label) do
      tag.div(class: ["flex overflow-hidden rounded-full bg-slate-100", height], role: "img", aria: {label: label}, data: {reveal: "left"}) do
        safe_join(parts.filter_map do |name, share, color, readings|
          next unless share.positive?

          tag.span(class: "h-full hover:opacity-75 data-active:opacity-75", style: "width: #{(share * 100).round(2)}%; background-color: #{color}",
            data: chart_tip(name, readings))
        end)
      end
    end
  end

  def meter(part, whole, label:)
    share = whole.to_i.zero? ? 0 : part.to_f / whole * 100
    tag.div(class: "h-2.5 overflow-hidden rounded-full bg-slate-200", role: "meter", aria: {label: label, valuenow: share.round(1), valuemin: 0, valuemax: 100}) do
      tag.div(class: "bg-progress-striped h-full rounded-full", style: "width: #{share.round(1)}%", data: {reveal: "left"})
    end
  end

  # Banded at a figure's own limits, so where it falls reads as good,
  # middling or poor at a glance. The scale runs half as far again past
  # poor, so a very slow page's mark still sits inside.
  def threshold_meter(value, good:, poor:, label:)
    top = poor * 1.5
    at = ->(figure) { (figure.to_f / top * 100).clamp(0, 100).round(2) }
    tag.div(class: "relative h-2.5", role: "meter", aria: {label: label, valuenow: value, valuemin: 0, valuemax: top}) do
      safe_join([
        tag.div(class: "absolute inset-0 flex overflow-hidden rounded-full", aria: {hidden: true}) do
          safe_join([
            tag.span(class: "bg-emerald-200", style: "width: #{at.(good)}%"),
            tag.span(class: "bg-amber-200", style: "width: #{(at.(poor) - at.(good)).round(2)}%"),
            tag.span(class: "flex-1 bg-red-200")
          ])
        end,
        tag.span(class: "absolute -inset-y-1 w-1 -translate-x-1/2 rounded-full bg-slate-900 ring-2 ring-white", style: "left: #{at.(value)}%",
          aria: {hidden: true})
      ])
    end
  end

  private

  # The overlay is HTML because the stretched SVG would squash round marks
  # out of shape.
  def chart_frame(keys, max, label, y_title:, x_title: nil, crosshair: false, lines: false, per: :day, overlay: nil, left: true, right: nil, zoom: true)
    max = [max.to_f, 1].max
    x_title ||= DATE_AXIS_TITLES.fetch(per) if keys.first.respond_to?(:strftime)
    tag.figure(class: "min-w-0") do
      safe_join([
        chart_tooltip(label: label, crosshair: crosshair) do
          tag.div(class: "flex") do
            safe_join([
              (y_axis_title(y_title) if left),
              (y_axis([compact_number(max), compact_number(max / 2.0), "0"]) if left),
              tag.div(class: ["relative min-w-0 flex-1", (zoom_cursor(keys, per) if zoom)]) do
                safe_join([
                  tag.svg(viewBox: "0 0 #{CHART_WIDTH} #{CHART_HEIGHT}", preserveAspectRatio: "none", role: "img", aria: {label: label},
                    class: "block h-32 w-full overflow-visible", data: {reveal: lines ? "left" : "up"}) { safe_join([grid_lines, yield(max)]) },
                  overlay&.call(max)
                ].compact)
              end,
              right
            ].compact)
          end
        end,
        x_axis(keys, format: DATE_AXIS_FORMATS[per], lines: lines, per: per, inset: [(left ? "ml-14" : "ml-0"), ("mr-14" if right)]),
        axis_title(x_title, class: [(left ? "ml-14" : "ml-0"), ("mr-14" if right), "text-center"])
      ])
    end
  end

  # Cut short so a long name never pushes the figure off the row; the row's
  # own readout carries the whole of it.
  def chart_row_name(name, url, **options)
    classes = ["truncate font-medium text-slate-700", options[:class]]
    return tag.span(name, class: classes) unless url

    link_to(name, url, class: [*classes, "hover:text-slate-900 hover:underline"])
  end

  # A thick stroke rather than a filled wedge, so the hole needs no second
  # shape.
  def donut_stroke(color)
    {fill: "none", stroke: color, "stroke-width": 16,
     class: "transition-[stroke-width,opacity] hover:[stroke-width:19] hover:opacity-90 data-active:[stroke-width:19] data-active:opacity-90"}
  end

  def axis_title(text, **options)
    tag.p(text, class: ["text-xs font-medium text-slate-500", options[:class]], style: options[:style], aria: {hidden: true})
  end

  # Turned to run up the axis so it takes a column's width rather than a
  # row's height, and cut short rather than stretch the chart.
  def y_axis_title(text, color: nil, tall: false)
    tag.div(class: ["flex w-4 shrink-0 items-center justify-center", tall ? "h-56" : "h-32"], aria: {hidden: true}) do
      tag.span(text, style: ("color: #{color}" if color),
        class: ["truncate text-xs font-medium text-slate-500 [writing-mode:vertical-rl] rotate-180", tall ? "max-h-56" : "max-h-32"])
    end
  end

  # Round steps, so the axis reads in round numbers whatever the largest
  # value is; whole and never under one, since what's ranked are counts.
  def axis_scale(max)
    max = [max.to_f, 1.0].max
    raw = max / 4
    magnitude = 10.0**Math.log10(raw).floor
    step = [[1, 2, 2.5, 5, 10].map { |factor| factor * magnitude }.find { |candidate| candidate >= raw && (candidate % 1).zero? }, 1.0].max
    [step, (max / step).ceil * step]
  end

  # Compared only when there is a period to compare with, so a figure never
  # shows a made-up change.
  def map_reading(name, count, before, previous_name)
    return [{value: number_with_delimiter(count), name: name}] unless before

    compared_readings(name, number_with_delimiter(count), number_with_delimiter(before), previous_name, current_value: count, before_value: before)
  end

  def map_reveal_delay(count, max)
    return 0 if max.zero?

    ((1 - Math.log(count + 1) / Math.log(max + 1)) * MAP_REVEAL_MS).round
  end

  def map_fill(count, max)
    return MAP_EMPTY_FILL if count.zero?

    MAP_FILLS[[(Math.log(count + 1) / Math.log(max + 1) * (MAP_FILLS.size - 1)).round, MAP_FILLS.size - 1].min]
  end

  # Outlined rather than filled, since the fill already says how many; a
  # country with none in either period is left plain.
  def map_outline(count, before)
    return ["stroke-white", 0.5] if count == before

    [count > before ? "stroke-emerald-600" : "stroke-red-600", 1.5]
  end

  def map_legend(max, unit, compared: false)
    return "".html_safe if max.zero?

    tag.div(class: "mt-2 flex flex-wrap items-center gap-x-3 gap-y-1 text-xs text-slate-500") do
      safe_join([
        *(compared ? [["ring-emerald-600", "Up on the period compared with"], ["ring-red-600", "Down on it"]] : []).map do |ring, text|
          tag.span(class: "inline-flex items-center gap-1") { safe_join([tag.span(class: "h-2.5 w-4 rounded-sm bg-white ring-2 #{ring}"), text]) }
        end,
        tag.span(class: "inline-flex items-center gap-1") do
          safe_join([tag.span(class: "h-2.5 w-4 rounded-sm bg-[#f0efec] ring-1 ring-slate-200"), "None"])
        end,
        tag.span(class: "inline-flex items-center gap-1") do
          safe_join([
            "1",
            tag.span(class: "flex", aria: {hidden: true}) { safe_join(MAP_SWATCHES.map { |swatch| tag.span(class: "h-2.5 w-4 #{swatch}") }) },
            "#{compact_number(max)} #{unit.pluralize}"
          ])
        end
      ])
    end
  end

  def share_legend(keys, key_label)
    entries = keys.zip(SHARE_SWATCHES).map { |key, swatch| [key_label.(key), swatch] } + [["Other", SHARE_OTHER_SWATCH]]
    tag.ul(class: "mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600") do
      safe_join(entries.map do |name, swatch|
        tag.li(class: "inline-flex items-center gap-1.5") { safe_join([tag.span(class: "size-2.5 rounded-sm #{swatch}"), name]) }
      end)
    end
  end

  def chart_legend(series, selectable: false, events: nil)
    tag.ul(class: "mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600") do
      event_key = tag.li(class: "inline-flex items-center gap-1.5") { safe_join([marker_svg(EVENT_MARKER, EVENT_COLOR, size: 10), events]) } if events
      safe_join([*series.each_with_index.map do |line, index|
        swatch =
          if line.marker
            marker_svg(line.marker, line.color || LINE_COLORS.fetch(index, LINE_COLORS.last), size: 10, opacity: (EARLIER_OPACITY if line.against))
          else
            tag.svg(width: 18, height: 6, aria: {hidden: true}, class: (line_class(index) unless line.color), style: ("opacity: #{EARLIER_OPACITY}" if line.against)) do
              tag.line(x1: 0, x2: 18, y1: 3, y2: 3, stroke: line.color || "currentColor", "stroke-width": 2, "stroke-dasharray": line.dasharray,
                "stroke-linecap": ("round" if line.dotted))
            end
          end
        key = safe_join([swatch, line.name])
        tag.li(class: "inline-flex items-center gap-1.5") do
          next key unless selectable

          tag.button(key, type: "button", title: "Pick out #{line.name}; pick others to compare", aria: {pressed: false},
            class: "inline-flex items-center gap-1.5 rounded transition-opacity hover:text-slate-900 aria-pressed:font-semibold aria-pressed:text-slate-900",
            data: {series: index, series_highlight_target: "toggle",
                   action: "click->series-highlight#toggle mouseenter->series-highlight#preview mouseleave->series-highlight#restore"})
        end
      end, event_key].compact)
    end
  end

  # Ticks sit on the gridlines rather than the labels, so each one points at
  # the exact height its label names.
  def y_axis(labels, side: :left, color: nil, tall: false)
    left = side == :left
    tag.div(class: ["relative flex w-10 shrink-0 flex-col justify-between text-xs tabular-nums", tall ? "h-56" : "h-32", ("text-slate-400" unless color),
      left ? "border-r border-slate-300 pr-2 text-right" : "border-l border-slate-300 pl-2 text-left"],
      style: ("color: #{color}" if color), aria: {hidden: true}) do
      safe_join([
        *labels.map { |text| tag.span(text) },
        *%w[top-0 top-1/2 bottom-0].map { |place| tag.span(class: "absolute #{left ? "-right-px" : "-left-px"} #{place} h-px w-1.5 bg-slate-300") }
      ])
    end
  end

  # Titled and labelled in its line's colour, which is all that ties an axis
  # to its line once there are several.
  def measure_axis(measure, top, side:, outer:, tall: true)
    labels = [top, top / 2.0, 0].map { |value| measure.tick.(value) }
    labels.reverse! if measure.inverted
    parts = [y_axis_title(measure.name, color: measure.color, tall: tall), y_axis(labels, side: side, color: measure.color, tall: tall)]
    tag.div(class: ["shrink-0", outer ? "hidden sm:flex" : "flex", ("ml-1" if side == :right && outer), ("mr-1" if side == :left && outer)]) do
      safe_join(side == :left ? parts : parts.reverse)
    end
  end

  # Rounded up to a step a reader can halve in their head, at any size,
  # since a rate's scale runs well below one. A count's top halves to a
  # whole number, since half a click can't happen.
  def round_top(max, whole: false)
    return whole ? 2.0 : 1.0 unless max.positive?

    magnitude = 10.0**Math.log10(max).floor
    factors = if !whole then [1, 2, 2.5, 5, 10]
    elsif magnitude < 10 then [2, 4, 6, 8, 10]
    else [1, 2, 4, 6, 8, 10]
    end
    magnitude = [magnitude, 1].max if whole
    # The tolerance stops float error bumping an exact step up to the next.
    factors.map { |factor| factor * magnitude }.find { |candidate| candidate >= max * (1 - 1e-9) }
  end

  # A day without data breaks the line, so a missing import doesn't read as
  # a day with nothing in it.
  def line_runs(values)
    values.each_with_index.chunk_while { |(a, _), (b, _)| !a.nil? && !b.nil? }.reject { |run| run.first.first.nil? }
  end

  # Categories get every label since each bar is its own bucket. A date
  # label is pinned inside only where centring would cut it off at the
  # card's edge, so a few weeks or months still sit under their points; its
  # tick stays on the mark so a pinned label still points at its point.
  CATEGORY_LABELS_FLAT = 6
  CATEGORY_LABEL_LENGTH_FLAT = 5

  def x_axis(keys, format: nil, inset: "ml-14", lines: false, per: nil)
    return "".html_safe if keys.empty?

    unless keys.first.respond_to?(:strftime)
      # Past this many, or a name this long, they run into each other, so they stand upright.
      upright = keys.size > CATEGORY_LABELS_FLAT || keys.any? { |key| key.to_s.size > CATEGORY_LABEL_LENGTH_FLAT }
      return tag.div(class: ["relative flex border-t border-slate-300 pt-1.5 text-xs text-slate-400", inset], aria: {hidden: true}) do
        safe_join([
          *keys.map do |key|
            if upright
              tag.span(class: "flex flex-1 justify-center") do
                tag.span(key.to_s, class: "max-h-24 truncate [writing-mode:vertical-rl] rotate-180")
              end
            else
              tag.span(key.to_s, class: "flex-1 truncate text-center")
            end
          end,
          *keys.each_index.map { |index| x_tick(index, keys.size) }
        ])
      end
    end

    format ||= keys.first.year == keys.last.year ? "%-d %b" : "%-d %b %Y"
    day_of_hours = per == :hour && keys.map(&:to_date).uniq.one?
    format = "%H:00" if day_of_hours
    ticks = day_of_hours ? hour_tick_indexes(keys) : tick_indexes(keys.size)
    # Six dates run into each other on a phone; both ends are kept so the
    # chart says where it starts and where it ends.
    narrow = if ticks.size <= 3 then ticks
    elsif ticks.size.odd? then ticks.each_slice(2).map(&:first)
    else [ticks.first, (ticks[ticks.size / 2 - 1] if ticks.size > 4), ticks.last].compact
    end
    tag.div(class: ["relative h-5.5 border-t border-slate-300 text-xs text-slate-400", inset], aria: {hidden: true}) do
      safe_join(ticks.flat_map do |index|
        center = x_percent(index, keys.size, lines)
        pinned = if center < EDGE_LABEL_ROOM then :left elsif center > 100 - EDGE_LABEL_ROOM then :right end
        position = {left: "left: 0%", right: "right: 0%"}.fetch(pinned, "left: #{center}%")
        hidden = ("max-sm:hidden" unless narrow.include?(index))
        [tag.span(l(keys[index], format: format), style: position,
          class: ["absolute top-1.5 whitespace-nowrap", ("-translate-x-1/2" unless pinned), hidden]),
         x_tick(index, keys.size, lines: lines, class: hidden)]
      end)
    end
  end

  # Every gap is the same whole number of hours, from the first multiple of
  # the step, so labels land on round hours.
  def hour_tick_indexes(keys)
    step = HOUR_STEPS.find { |hours| keys.size / hours < MAX_TICKS } || HOUR_STEPS.last
    first = keys.index { |key| (key.hour % step).zero? }
    first ? first.step(keys.size - 1, step).to_a : tick_indexes(keys.size)
  end

  def x_tick(index, size, lines: false, **options)
    tag.span(class: ["absolute top-0 h-1 w-px bg-slate-300", options[:class]], style: "left: #{x_percent(index, size, lines)}%")
  end

  # Bars each fill a slot, so they're marked at its middle; lines run from
  # axis to axis, so their first and last points sit on the axes.
  def x_percent(index, size, lines)
    lines ? (point_x(index, size) / CHART_WIDTH * 100).round(2) : ((index + 0.5) / size * 100).round(2)
  end

  # A lone point has no line to run, so it's centred.
  def point_x(index, size)
    size > 1 ? (index * CHART_WIDTH.to_f / (size - 1)).round(2) : CHART_WIDTH / 2.0
  end

  # Reaches halfway to each neighbour, so the nearest point is the one read;
  # the ends stop at the axes.
  def point_hit(index, size)
    half = size > 1 ? CHART_WIDTH.to_f / (size - 1) / 2 : CHART_WIDTH / 2.0
    from = [point_x(index, size) - half, 0.0].max
    to = [point_x(index, size) + half, CHART_WIDTH].min
    {x: from.round(2), width: (to - from).round(2)}
  end

  # A whole number of points apart, so every gap between labels is the same
  # width. Both ends when a step divides the axis into enough labels;
  # otherwise counted back from the latest, the point most often looked for.
  def tick_indexes(size)
    last = size - 1
    return [0] if last.zero?

    shortest = (last / (MAX_TICKS - 1.0)).ceil
    step = (shortest..last).find { |gap| (last % gap).zero? && last / gap + 1 >= MIN_TICKS }
    step ? 0.step(last, step).to_a : last.step(0, -shortest).to_a.reverse
  end

  # No zero line, because the x axis border beneath already draws one.
  def grid_lines
    safe_join([0, CHART_HEIGHT / 2].map do |y|
      tag.line(x1: 0, x2: CHART_WIDTH, y1: y, y2: y, stroke: "currentColor", class: "text-slate-200", "vector-effect": "non-scaling-stroke")
    end)
  end

  # Hit areas are the full column height, so a short bar is as easy to hover
  # as a tall one.
  def bar_marks(points, max, unit, per, events = {}, event_name = nil, unsettled: nil, previous: nil, previous_name: nil, metric: nil, zoom: true)
    slot = CHART_WIDTH.to_f / [points.size, 1].max
    gap = [slot * 0.2, 2].min
    earlier = previous && previous_chart_keys(points.map(&:first), per)
    safe_join(points.each_with_index.map do |(key, value), index|
      height = value.to_f / max * CHART_HEIGHT
      reading = value.nil? ? "No data" : "#{number_with_delimiter(value)}#{unit}"
      title = time_tip_title(key, per, index, previous)
      rows = [{**compared_name(metric, key, per, previous), value: reading, color: BAR_COLOR}]
      if previous
        before = previous[index]
        rows.first.merge!(change: compare_change(value, before), tone: (value <=> before if value && before)).compact!
        rows << {**compared_name(metric, earlier&.at(index), per, true, previous_name), value: before.nil? ? "No data" : "#{number_with_delimiter(before)}#{unit}",
                 color: BAR_COLOR, dotted: true, earlier: true}
      end
      rows += events.fetch(key, []).map { |name| {name: event_name, value: name, color: EVENT_COLOR, marker: EVENT_MARKER} }
      tag.g(class: "group", data: chart_tip(title, rows, note: unsettled_note(key, per, unsettled), key: (zoom_key(key, per) if zoom))) do
        safe_join([
          tag.rect(x: (index * slot).round(2), y: 0, width: slot.round(2), height: CHART_HEIGHT, fill: "transparent"),
          tag.rect(x: (index * slot + gap / 2).round(2), y: (CHART_HEIGHT - height).round(2), width: (slot - gap).round(2),
            height: height.round(2), class: "fill-slate-600 group-hover:fill-slate-900 group-data-active:fill-slate-900")
        ])
      end
    end)
  end

  # Parts are inset by a gap, so touching colours stay apart; a day with no
  # data has no bar and no readout, so it isn't read as a day of none.
  def stacked_marks(keys, series, max, per, titles = nil, unsettled: nil, previous: nil, previous_name: nil, line: nil, line_top: nil, total_name: nil)
    slot = CHART_WIDTH.to_f / [keys.size, 1].max
    gap = [slot * 0.2, 2].min
    earlier = previous && previous_chart_keys(keys, per)
    safe_join(keys.each_with_index.filter_map do |key, index|
      next if series.all? { |part| part.values[index].nil? } && previous&.at(index).nil? && line&.values&.at(index).nil?

      y = CHART_HEIGHT.to_f
      parts = series.filter_map do |part|
        height = [part.values[index].to_f, 0].max / max * CHART_HEIGHT
        y -= height
        next if height.zero?

        tag.rect(x: (index * slot + gap / 2).round(2), y: y.round(2), width: (slot - gap).round(2), height: height.round(2), fill: part.color,
          class: "stroke-white", "stroke-width": 1, "vector-effect": "non-scaling-stroke")
      end
      # A part not recorded beside others that were reads as unknown, not as none.
      rows = series.map do |part|
        value = part.values[index]
        {value: value.nil? ? "No data" : number_with_delimiter(value.to_i), **compared_name(part.name, key, per, previous), color: part.color}
      end
      if line
        value = line.values[index]
        rows << {value: value.nil? ? "No data" : line.reading.(value), **compared_name(line.name, key, per, previous), color: line.color,
                 y: (((1 - value.to_f / [line_top.to_f, 1].max) * CHART_HEIGHT).round(2) unless value.nil?)}.compact
      end
      total = series.sum { |part| part.values[index].to_i }
      if previous
        before = previous[index]
        rows << {value: number_with_delimiter(total), **compared_name(total_name || "Total", key, per, true), color: BAR_COLOR,
                 change: compare_change(total, before), tone: (total <=> before if before)}.compact
        rows << {value: before.nil? ? "No data" : number_with_delimiter(before), **compared_name(total_name || "Total", earlier&.at(index), per, true, previous_name),
                 color: BAR_COLOR, dotted: true, earlier: true}
      elsif total_name
        rows << {value: number_with_delimiter(total), **compared_name(total_name, key, per, previous), color: BAR_COLOR}
      end
      tag.g(class: "group", data: chart_tip(titles&.at(index) || time_tip_title(key, per, index, previous), rows, note: unsettled_note(key, per, unsettled), key: zoom_key(key, per))) do
        safe_join([
          tag.rect(x: (index * slot).round(2), y: 0, width: slot.round(2), height: CHART_HEIGHT, fill: "transparent",
            class: "group-hover:fill-slate-900/5 group-data-active:fill-slate-900/5"),
          *parts
        ])
      end
    end)
  end

  def event_legend(name)
    tag.ul(class: "mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600") do
      tag.li(class: "inline-flex items-center gap-1.5") { safe_join([marker_svg(EVENT_MARKER, EVENT_COLOR, size: 10), name]) }
    end
  end

  def swatch_legend(entries, dotted: nil, selectable: false)
    dotted_key = if dotted
      tag.li(class: "inline-flex items-center gap-1.5") do
        line = tag.svg(width: 18, height: 6, aria: {hidden: true}) do
          tag.line(x1: 1, x2: 17, y1: 3, y2: 3, stroke: BAR_COLOR, "stroke-width": 2, "stroke-dasharray": "0 4", "stroke-linecap": "round")
        end
        safe_join([line, dotted])
      end
    end
    tag.ul(class: "mb-2 flex flex-wrap gap-x-4 gap-y-1 text-xs text-slate-600") do
      safe_join([
        *entries.each_with_index.map do |(name, color, line), index|
          swatch = if line
            tag.svg(width: 18, height: 6, aria: {hidden: true}) { tag.line(x1: 0, x2: 18, y1: 3, y2: 3, stroke: color, "stroke-width": 2) }
          else
            tag.span(class: "size-2.5 rounded-sm", style: "background-color: #{color}")
          end
          key = safe_join([swatch, name])
          tag.li(class: "inline-flex items-center gap-1.5") do
            next key unless selectable

            tag.button(key, type: "button", title: "Pick out #{name}; pick others to compare", aria: {pressed: false},
              class: "inline-flex cursor-pointer items-center gap-1.5 rounded transition-opacity hover:text-slate-900 aria-pressed:font-semibold aria-pressed:text-slate-900",
              data: {series: index, series_highlight_target: "toggle",
                     action: "click->series-highlight#toggle mouseenter->series-highlight#preview mouseleave->series-highlight#restore"})
          end
        end,
        dotted_key
      ].compact)
    end
  end

  # Through the middle of each bar's slot, so a point sits over the bar it's
  # read against; broken where a day has no data, as a line is. Haloed in
  # white so it shows over a bar of any shade.
  def previous_bars_line(keys, previous, max)
    slot = CHART_WIDTH.to_f / [keys.size, 1].max
    safe_join(line_runs(previous).flat_map do |run|
      # Held at the axis below zero, as there are no bars there to read it against; the readout gives the figure.
      points = run.map { |value, i| "#{((i + 0.5) * slot).round(2)},#{(CHART_HEIGHT - [value.to_f, 0].max / max * CHART_HEIGHT).round(2)}" }.join(" ")
      [["white", 4, "0 4"], [BAR_COLOR, 2, "0 4"]].map do |stroke, width, dashes|
        tag.polyline(points: points, fill: "none", stroke: stroke, "stroke-width": width, "stroke-linejoin": "round", "stroke-linecap": "round",
          "stroke-dasharray": dashes, "vector-effect": "non-scaling-stroke", class: "pointer-events-none", data: {previous: ""})
      end
    end)
  end

  # The first series is filled beneath, so the main figure stands out from
  # the ones it's compared against.
  def line_marks(keys, series, max, unit, per, events = {}, event_name = nil, unsettled: nil, y_title: nil)
    x = ->(index) { point_x(index, keys.size) }
    y = ->(value) { (CHART_HEIGHT - value.to_f / max * CHART_HEIGHT).round(2) }
    lines = series.each_with_index.flat_map do |line, index|
      line_runs(line.values).map do |run|
        tag.polyline(points: run.map { |value, i| "#{x.(i)},#{y.(value)}" }.join(" "), fill: "none", stroke: line.color || "currentColor",
          "stroke-width": 2, "stroke-linejoin": "round", "stroke-dasharray": line.dasharray, "stroke-linecap": ("round" if line.dotted), "stroke-opacity": (EARLIER_OPACITY if line.against),
          "vector-effect": "non-scaling-stroke", class: [(line_class(index) unless line.color), "pointer-events-none transition-opacity"],
          data: {series: index, series_line: ""})
      end
    end
    # Broken where the line is, so a day without data isn't shaded as none.
    areas = line_runs(series.first.values).map do |run|
      tag.polygon(points: "#{x.(run.first.last)},#{CHART_HEIGHT} #{run.map { |value, i| "#{x.(i)},#{y.(value)}" }.join(" ")} #{x.(run.last.last)},#{CHART_HEIGHT}",
        fill: "url(#area-fade)", class: "transition-opacity", data: {series: 0})
    end
    # Fading to nothing at the baseline, so the area reads as a wash under the
    # line rather than a slab; the same in every chart, so any one's serves.
    fade = tag.defs do
      tag.linearGradient(id: "area-fade", x1: 0, x2: 0, y1: 0, y2: 1) do
        safe_join([tag.stop(offset: "0%", "stop-color": "#94a3b8", "stop-opacity": 0.35), tag.stop(offset: "100%", "stop-color": "#94a3b8", "stop-opacity": 0.02)])
      end
    end
    # One readout per day for every series, so no line has to be hit to be
    # read.
    compared = series.any?(&:against)
    # A compared line is named for what it is the earlier period of, so both
    # read as the same figure on different days.
    metric = ->(line) { metric_name(series, line.against || line, y_title) }
    earlier = series.map { |line| (line.keys || previous_chart_keys(keys, per)) if line.against }
    hits = keys.each_with_index.map do |key, index|
      rows = series.each_with_index.map do |line, line_index|
        value = line.values[index]
        {value: value.nil? ? "No data" : "#{number_with_delimiter(value)}#{unit}",
         **compared_name(metric.(line), (earlier[line_index] || keys)[index], per, compared, (previous_period_name || line.name if line.against)),
         color: line.color || LINE_COLORS.fetch(line_index, LINE_COLORS.last), dashed: (true if line.dashed), dotted: (true if line.dotted),
         marker: line.marker, earlier: (true if line.against), y: (y.(value) unless value.nil?)}.compact
      end
      series.each_with_index do |line, line_index|
        before = series.find { |other| other.against.equal?(line) }&.values&.at(index)
        next if before.nil? || line.values[index].nil?

        rows[line_index].merge!(change: compare_change(line.values[index], before), tone: line.values[index] <=> before)
      end
      rows += events.fetch(key, []).map { |name| {name: event_name, value: name, color: EVENT_COLOR, marker: EVENT_MARKER} }
      tag.rect(**point_hit(index, keys.size), y: 0, height: CHART_HEIGHT, fill: "transparent",
        data: chart_tip(time_tip_title(key, per, index, compared), rows, x: x.(index), note: unsettled_note(key, per, unsettled), key: zoom_key(key, per)))
    end
    safe_join([fade, *areas, *lines.reverse, *hits])
  end

  # Nothing where either period has no data, so no change is made up, nor
  # from a figure below zero, which a percentage change can't be read from.
  def compare_change(current, before)
    CompareChange.label(current, before) unless current.nil? || before.nil? || current.negative? || before.negative?
  end

  # So a line's ends are found at a glance and a line of one point still
  # shows.
  def line_end_markers(keys, series, max)
    safe_join(series.each_with_index.flat_map do |line, index|
      known = line.values.each_index.reject { |i| line.values[i].nil? }
      [known.first, known.last].compact.uniq.map do |i|
        position = "left: #{x_percent(i, keys.size, true)}%; top: #{(100 - line.values[i].to_f / max * 100).round(2)}%"
        color = line.color || LINE_COLORS.fetch(index, LINE_COLORS.last)
        if line.marker
          tag.span(marker_svg(line.marker, color, size: 10, outline: true),
            class: "pointer-events-none absolute flex -translate-x-1/2 -translate-y-1/2 transition-opacity", style: position, data: {series: index}, aria: {hidden: true})
        else
          tag.span(class: "pointer-events-none absolute size-2 -translate-x-1/2 -translate-y-1/2 rounded-full ring-2 ring-white transition-opacity",
            style: "#{position}; background-color: #{color}", data: {series: index}, aria: {hidden: true})
        end
      end
    end)
  end

  # On the axis rather than the line, so a mark never hides a point; the
  # day's readout names what happened.
  def event_markers(keys, events, lines: true)
    safe_join(events.keys.map do |key|
      tag.span(marker_svg(EVENT_MARKER, EVENT_COLOR, size: 10, outline: true),
        class: "pointer-events-none absolute bottom-0.5 flex -translate-x-1/2", style: "left: #{x_percent(keys.index(key), keys.size, lines)}%",
        data: {event: ""}, aria: {hidden: true})
    end)
  end

  # Outlined in white on a line, so it stands clear of the lines it sits on.
  def marker_svg(marker, color, size:, outline: false, opacity: nil)
    tag.svg(width: size, height: size, viewBox: "-1 -1 12 12", class: "shrink-0 overflow-visible", style: ("opacity: #{opacity}" if opacity), aria: {hidden: true}) do
      tag.path(d: MARKERS.fetch(marker), fill: color, stroke: ("#fff" if outline), "stroke-width": (2 if outline), "paint-order": ("stroke" if outline))
    end
  end

  def line_class(index)
    index.zero? ? "text-slate-800" : "text-slate-400"
  end

  def chart_key_label(key)
    key.respond_to?(:strftime) ? l(key, format: "%a, %-d %b %Y") : key.to_s
  end

  # So a week's or month's readout doesn't look like a single day's.
  def chart_bucket_label(key, per)
    return chart_key_label(key) unless key.respond_to?(:strftime)

    case per
    when :minute then key.strftime("%H:%M %Z")
    when :hour then key.strftime("%a, %-d %b %Y, %H:00 %Z")
    when :week then "Week of #{l(key)}"
    when :month then l(key, format: "%B %Y")
    else chart_key_label(key)
    end
  end

  # Without the comma the title keeps, so it stays short under a figure.
  def chart_period_label(key, per)
    return compact_period(chart_bucket_label(key, per)) unless key.respond_to?(:strftime)

    case per
    when :month then key.strftime("%b %Y")
    when :year then key.strftime("%Y")
    when :week, :day then key.strftime("%a, %-d %b %Y")
    else chart_bucket_label(key, per)
    end
  end

  # The year once when both ends share it, and no commas, so a range fits on
  # a line.
  def compact_period(text)
    range = text.to_s.sub(/\A(\d+ \w{3}), (\d{4}) – (\d+ \w{3}), (\d{4})\z/) { $2 == $4 ? "#{$1} – #{$3}, #{$4}" : $& }
    range.gsub(/, (\d{4})/, ' \1')
  end

  # A bucket by where it starts, so a day, a week and a month read the same
  # way beside each other.
  def chart_point_label(key, per)
    return chart_bucket_label(key, per) unless key.respond_to?(:strftime)

    case per
    when :month then key.strftime("%b %Y")
    when :year then key.strftime("%Y")
    when :week, :day then key.strftime("%a, %-d %b, %Y")
    else chart_bucket_label(key, per)
    end
  end

  # An hour is dated by its day as well, which a count of hours can't say.
  def positional?(per)
    %i[day week month year].include?(per)
  end

  # A readout is headed by its place in the period, with the date beside the
  # figures, since an earlier period beside it has different dates.
  def time_tip_title(key, per, index, compared)
    return chart_bucket_label(key, per) unless key.respond_to?(:strftime)

    compared || positional?(per) ? "#{per.to_s.capitalize} #{index + 1}" : chart_point_label(key, per)
  end

  # A figure beside an earlier period is read against it, so it needs the day
  # it is for; where the buckets aren't dates, the period's own name does that.
  def compared_name(metric, key, per, compared, period_name = nil)
    return {name: metric} unless compared || (key.respond_to?(:strftime) && positional?(per))

    period_name ||= current_period_name
    date = key.respond_to?(:strftime) ? chart_period_label(key, per) : (compact_period(period_name) if period_name)
    {name: metric, period: date}.compact
  end

  def previous_period_name
    @period.previous.to_s if @period.respond_to?(:compare?) && @period.compare?
  end

  # So the figure for this period says which it is, as the earlier one does.
  def current_period_name
    @period.to_s if @period.respond_to?(:compare?) && @period.compare?
  end

  # A lone figure is already named by the axis; among several each needs its
  # own name, and an earlier period's line takes its counterpart's so both
  # read as one figure.
  def metric_name(series, line, y_title)
    line.metric || (series.count { |other| other.against.nil? } == 1 ? y_title : (line.against || line).name)
  end

  # So each of the compared period's figures can be dated.
  def previous_chart_keys(keys, per)
    return unless @period.respond_to?(:previous) && @period.compare? && keys.first.respond_to?(:strftime)

    bucket = lambda do |date|
      case per
      when :week then date.beginning_of_week(keys.first.wday.zero? ? :sunday : :monday)
      when :month then date.beginning_of_month
      when :year then date.beginning_of_year
      when :day then date
      end
    end
    first = bucket.(@period.previous.from)
    return unless first

    # A chart started on its first figure rather than the period's first
    # day is set against the days as far into the period compared with.
    start = bucket.(@period.from)
    skipped = [buckets_between(start, keys.first.to_date, per), 0].max
    (skipped...skipped + keys.size).map do |index|
      case per
      when :week then first + (7 * index)
      when :month then first >> index
      when :year then first >> (12 * index)
      else first + index
      end
    end
  end

  def buckets_between(from, to, per)
    case per
    when :week then ((to - from) / 7).to_i
    when :month then (to.year * 12 + to.month) - (from.year * 12 + from.month)
    when :year then to.year - from.year
    else (to - from).to_i
    end
  end

  # The buckets before a chart's first figure, in this period or the one
  # compared with, would only draw as a flat line or no bars, so a chart over
  # dates starts where its data does, on that day, week or month. One with no
  # figures at all is left whole. Minutes and hours stay, as a window that
  # short is read whole.
  def leading_empty(keys, values)
    return 0 unless keys.first.instance_of?(Date)

    keys.each_index.find { |index| values.any? { |list| !list[index].nil? && list[index] != 0 } }.to_i
  end

  # Copies, so a caller's series are left as they were, with each compared
  # line still pointing at the copy of the line it's compared with.
  def trimmed_series(series, skip)
    return series unless skip.positive?

    copies = {}.compare_by_identity
    series.each { |line| copies[line] = line.dup.tap { |copy| copy.values, copy.keys = line.values.drop(skip), line.keys&.drop(skip) } }
    copies.each_value { |copy| copy.against = copies.fetch(copy.against, copy.against) if copy.against }
    copies.values
  end

  def compared_readings(metric, current, before, previous_name, color: nil, current_value: nil, before_value: nil)
    now = current_period_name
    [{name: metric, period: (compact_period(now) if now), value: current, color: color, change: compare_change(current_value, before_value),
      tone: (current_value <=> before_value if current_value && before_value)}.compact,
     {name: metric, period: compact_period(previous_name), value: before, color: color, dotted: true, earlier: true}.compact]
  end

  # A week or month counts as unsettled once any of its days is, so a total
  # still being added to doesn't read as final; an hour by the day it's in.
  def unsettled_note(key, per, unsettled)
    return unless unsettled && key.respond_to?(:to_date)

    last = case per
    when :week then key.to_date + 6
    when :month then key.to_date.end_of_month
    else key.to_date
    end
    UNSETTLED_NOTE if last >= unsettled
  end
end
