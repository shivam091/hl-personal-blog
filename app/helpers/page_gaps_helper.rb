# encoding: UTF-8

module PageGapsHelper
  ORDINARY_COLOR = ChartsHelper::SHARE_COLORS[0]
  FLAGGED_COLOR = ChartsHelper::SHARE_COLORS[3]
  FLAGGED_SWATCH = ChartsHelper::SHARE_SWATCHES[3]
  # Views marked on the log axis, so ticks land on round figures however busy the busiest page is.
  LOG_STEPS = [1, 2, 5].freeze
  MAX_LOG_TICKS = 7
  # GA counting twice our views is as far down as the chart goes, so one page GA counts many times over
  # can't squash the rest; it sits on the bottom edge, its figure in the tooltip.
  LOWEST_PERCENT = -1.0

  # Short, as they label a bar a few words wide; the consent report spells each out.
  CAUSES = {
    denied_gap: ["Declined", ChartsHelper::SHARE_COLORS[0]],
    pending_gap: ["Pending", ChartsHelper::SHARE_COLORS[1]],
    blocked_gap: ["Blocked", ChartsHelper::SHARE_COLORS[2]],
    unknown_gap: ["Undetected", ChartsHelper::SHARE_COLORS[3]],
    datacentre_gap: ["Datacentre", ChartsHelper::SHARE_COLORS[4]],
    remainder: ["Unexplained", ChartsHelper::SHARE_OTHER_COLOR]
  }.freeze

  def page_gap_percent(value)
    value ? number_to_percentage(value * 100, precision: 1) : "—"
  end

  def page_gap_color(row)
    row.flagged ? FLAGGED_COLOR : ORDINARY_COLOR
  end

  # Over the same period, so the page's statistics show the views being compared.
  def page_gap_link(row, period = @period)
    page_view_path(row.slug, **period&.query.to_h) if row.first_party.positive?
  end

  def page_gap_dumbbell(rows)
    step, top = axis_scale(rows.flat_map { |row| [row.first_party, row.analytics] }.max.to_f)
    dumbbell_chart(rows.map { |row| [row.slug, [row.first_party, row.analytics]] }, top: top, ticks: (0..(top / step).round).map { |index| (index * step).round },
      keys: [["Our views", ChartsHelper::LINE_COLORS.first, :circle], ["GA views", ORDINARY_COLOR, :square]],
      links: rows.to_h { |row| [row.slug, page_gap_link(row)] }, x_title: "Views", y_title: "Page",
      label: "Our views against GA's for each flagged page")
  end

  def page_gap_causes_key
    swatch_legend(CAUSES.values)
  end

  # Each part as a share of what the causes and the unexplained rest add up to, so the bar always fills;
  # an unexplained rest below zero means the causes found already cover more than the gap, so it is drawn as none.
  def page_gap_causes_bar(row, gap)
    return tag.span("No days with the consent split", class: "text-slate-400") unless gap

    parts = CAUSES.to_h { |cause, _| [cause, cause == :remainder ? [gap.remainder, 0].max : gap.sum(cause)] }
    total = parts.values.sum
    readings = CAUSES.map do |cause, (name, color)|
      share = share_of_total(parts[cause], gap.gap) if gap.gap.positive?
      {value: [number_with_delimiter(cause == :remainder ? gap.remainder : parts[cause]), share].compact.join(" · "), name: name, color: color}
    end
    note = "Over #{pluralize(gap.days.size, "day")} with the consent split, a gap of #{number_with_delimiter(gap.gap)}."
    note += " The causes found add up to more than the gap." if gap.over_counted?
    tag.div(class: "flex h-4 overflow-hidden rounded-sm bg-slate-100", data: chart_tip(row.slug, readings, note: note)) do
      next tag.span if total.zero?

      safe_join(CAUSES.filter_map do |cause, (_, color)|
        next if parts[cause].zero?

        tag.span(class: "h-full border-r border-white last:border-r-0", style: "width: #{(parts[cause].fdiv(total) * 100).round(2)}%; background-color: #{color}")
      end)
    end
  end

  # Views on a log scale, so the few busy pages don't crowd every other one into the left edge.
  def page_gap_scatter(page_gap)
    rows = page_gap.judged
    median = page_gap.median_percent
    threshold = page_gap.threshold
    ticks = log_ticks(PageGap::MIN_VIEWS, rows.map(&:first_party).max)
    percents = [*rows.map(&:percent), median, threshold]
    y_max = round_top(percents.max)
    y_min = percents.min.negative? ? -[round_top(-percents.min), -LOWEST_PERCENT].min : 0
    points = rows.map do |row|
      color = page_gap_color(row)
      ChartsHelper::ScatterPoint.new(x: Math.log10(row.first_party), y: row.percent, color: color,
        tip: chart_tip(row.slug, [
          {value: number_with_delimiter(row.first_party), name: "Our views"},
          {value: number_with_delimiter(row.analytics), name: "GA views"},
          {value: page_gap_percent(row.percent), name: "Gap", color: color}
        ], href: page_gap_link(row)))
    end
    lines = [{y: median, color: ChartsHelper::LINE_COLORS.first}, {y: threshold, color: FLAGGED_COLOR, dashed: true}]
    lines.unshift({y: 0, color: "#cbd5e1", width: 1}) if y_min.negative?
    scatter_chart(points, x_min: Math.log10(ticks.first), x_max: Math.log10(ticks.last), x_ticks: ticks.map { |tick| Math.log10(tick) },
      x_tick: ->(tick) { compact_number(10**tick) }, y_min: y_min, y_max: y_max, y_tick: ->(value) { axis_value(value, :percent) },
      lines: lines, x_title: "Our views (log scale)", y_title: "Gap", label: "Each page's gap against its views, with the median and where a page is flagged",
      key: [["Ordinary", ORDINARY_COLOR], ["Well above the median", FLAGGED_COLOR]])
  end

  # Round 1-2-5 steps, as a log axis marked at odd figures can't be read at a glance; only the powers of
  # ten when the steps would crowd the axis.
  def log_ticks(low, high)
    steps = (0..).lazy.flat_map { |power| LOG_STEPS.map { |step| step * 10**power } }.select { |tick| tick > low }
    last = steps.find { |tick| tick >= high }
    between = steps.take_while { |tick| tick < last }.to_a
    between = between.select { |tick| tick.digits.sum == 1 } if between.size > MAX_LOG_TICKS - 2
    [low, *between, last]
  end
end
