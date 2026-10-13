# encoding: UTF-8

# One way of reading a slow tail, so a 95th percentile means the same on
# every report.
module Percentile
  private

  # Nearest rank, so the figure is always a time a call actually took.
  def percentile(values, share)
    return if values.blank?

    sorted = values.sort
    sorted[[(share * sorted.size).ceil - 1, 0].max]
  end
end
