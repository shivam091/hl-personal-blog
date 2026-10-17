# encoding: UTF-8

# Kept in the URL like any list state, so picking another period or country
# keeps the blog's charts in the buckets chosen, as the Google reports do.
class ChartGranularity
  # Weeks start on Monday, as the blog's weekly counts do; the Google
  # reports start them on Sunday, as GA's do.
  def self.buckets(week_start)
    {
      "day" => ->(date) { date },
      "week" => ->(date) { date.beginning_of_week(week_start) },
      "month" => ->(date) { date.beginning_of_month },
      "year" => ->(date) { date.beginning_of_year }
    }.freeze
  end

  BUCKETS = buckets(:monday)
  OPTIONS = BUCKETS.keys.map { |bucket| [bucket.capitalize, bucket] }.freeze

  # A bucket only sorts a period's days into groups when the period is longer
  # than the bucket, so a week of days has no use for weeks, months or years.
  LENGTHS = {"day" => 1, "week" => 7, "month" => 31, "year" => 366}.freeze

  # Day first and always, as a period always has days to show.
  def self.allowed(period)
    return BUCKETS.keys unless period

    BUCKETS.keys.select { |bucket| bucket == "day" || period.days > LENGTHS.fetch(bucket) }
  end

  # Nothing to choose between while only days make sense.
  def self.options(period)
    allowed(period).size > 1 ? OPTIONS.select { |_, bucket| allowed(period).include?(bucket) } : []
  end

  # A bucket asked for in the URL that the period is too short for, such as
  # years carried over to a week, reads as days.
  def self.clamp(bucket, period, keys: BUCKETS.keys)
    asked = bucket.presence_in(keys) || "day"
    allowed(period).include?(asked) ? asked : "day"
  end

  attr_reader :by

  def initialize(params, period: nil)
    @by = self.class.clamp(params[:chart_by], period)
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

  # Of a period's days, so a figure for the period compared with is bucketed
  # as the one for this period is.
  def sums_for(period, values)
    sums((period.from..period.to).to_a, values)
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
