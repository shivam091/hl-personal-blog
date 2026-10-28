# encoding: UTF-8

# Kept in the URL like any list state, so picking another period or country
# keeps the blog's charts in the buckets chosen, as the Google reports do.
class ChartGranularity
  # Weeks start on Monday, as the blog's weekly counts do.
  BUCKETS = {
    "day" => ->(date) { date },
    "week" => ->(date) { date.beginning_of_week },
    "month" => ->(date) { date.beginning_of_month }
  }.freeze

  attr_reader :by

  def initialize(params)
    @by = params[:chart_by].presence_in(BUCKETS.keys) || "day"
  end

  def query
    by == "day" ? {} : {chart_by: by}
  end

  def per
    by.to_sym
  end

  def dates(dates)
    dates.map(&BUCKETS.fetch(by)).uniq
  end

  # Nil where every day in a bucket is, so a bucket nothing was synced for
  # isn't drawn as a real zero.
  def sums(dates, values)
    dates.each_index.group_by { |index| BUCKETS.fetch(by).(dates[index]) }.values.map do |indexes|
      values.values_at(*indexes).compact.then { |known| known.sum if known.any? }
    end
  end

  # Under the bucket each day falls in, so a marker still lands on its bar.
  def events(events)
    events.each_with_object({}) { |(date, names), buckets| (buckets[BUCKETS.fetch(by).(date)] ||= []).concat(names) }
  end
end
