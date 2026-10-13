# frozen_string_literal: true

# One wording for a change against the period before, so a table and its
# export never read it differently.
module CompareChange
  NONE_IN_EITHER = "(–)"
  NEW = "(new)"
  UNCHANGED = "(0%)"

  module_function

  # The brackets are part of it, as under a figure in a table.
  def label(current, previous, minus: "−")
    current = current.to_f
    previous = previous.to_f
    return NONE_IN_EITHER if current.zero? && previous.zero?
    return NEW if previous.zero?

    change = (current - previous) / previous
    return UNCHANGED if change.abs < 0.0005

    percent = ActiveSupport::NumberHelper.number_to_percentage(change.abs * 100, precision: 1, strip_insignificant_zeros: true)
    "(#{change.positive? ? "+" : minus}#{percent})"
  end

  # A plain minus, since spreadsheets read it as one; nothing beside the
  # figure when there's nothing to compare it with.
  def cell(value, previous, compare: true)
    return value unless compare && !value.nil?

    "#{value} #{label(value, previous, minus: "-")}"
  end
end
