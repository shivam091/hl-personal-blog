# encoding: UTF-8

module PageGapsHelper
  ORDINARY_COLOR = ChartsHelper::SHARE_COLORS[0]
  FLAGGED_COLOR = ChartsHelper::SHARE_COLORS[3]
  # Views marked on the log axis, so ticks land on round figures however busy the busiest page is.
  LOG_STEPS = [1, 2, 5].freeze
  MAX_LOG_TICKS = 7
  # GA counting twice our views is as far down as the chart goes, so one page GA counts many times over
  # can't squash the rest; it sits on the bottom edge, its figure in the tooltip.
  LOWEST_PERCENT = -1.0

  def page_gap_percent(value)
    value ? number_to_percentage(value * 100, precision: 1) : "—"
  end

  def page_gap_color(row)
    row.flagged ? FLAGGED_COLOR : ORDINARY_COLOR
  end

  def page_gap_link(row)
    page_view_path(row.slug) if row.first_party.positive?
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
