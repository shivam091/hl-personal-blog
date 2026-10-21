# encoding: UTF-8

module PageGapShiftsHelper
  # Beside a page's GA views, so a change that is partly tracking isn't read as readers coming or going.
  def gap_shift_note(shift)
    return unless shift

    message = "GA's share of this page changed from #{gap_share(shift.before)} to #{gap_share(shift.now)} — " \
              "part of this change may be tracking, not readers"
    tag.span(class: "block basis-full whitespace-nowrap text-xs text-amber-700", title: message) do
      safe_join([icon("alert-triangle", size: 12, class: "mr-1 inline align-[-1px]"), "GA share #{gap_share(shift.before)} → #{gap_share(shift.now)}"])
    end
  end

  private

  def gap_share(fraction)
    number_to_percentage(fraction * 100, precision: 0)
  end
end
