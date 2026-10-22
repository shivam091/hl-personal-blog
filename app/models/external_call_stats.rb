# encoding: UTF-8

# The outside services read as a whole, so one that's started refusing or
# slowing down shows before a sync fails because of it.
class ExternalCallStats
  include Percentile
  include PreviousPeriod

  # Enough to keep each service its own colour in a stacked bar.
  CHART_SERVICES = 5

  ServiceRow = Struct.new(:service, :calls, :failed, :median_ms, :p95_ms, :last_failure, keyword_init: true) do
    def failure_rate
      failed.fdiv(calls)
    end
  end
  ErrorRow = Struct.new(:service, :error, :count, :last_at, keyword_init: true)

  attr_reader :period

  def initialize(period)
    @period = period
  end

  def calls
    @calls ||= ExternalCall.where(created_at: period.from.in_time_zone.beginning_of_day..period.to.in_time_zone.end_of_day)
      .only(:service, :status, :duration_ms, :error, :created_at).to_a
  end

  def any?
    calls.any?
  end

  def total
    calls.size
  end

  def failed
    calls.count(&:failed?)
  end

  def median_ms
    percentile(calls.filter_map(&:duration_ms), 0.5)
  end

  def p95_ms
    percentile(calls.filter_map(&:duration_ms), 0.95)
  end

  def dates
    (period.from..period.to).to_a
  end

  # The busiest services keep their own part, the rest share Other, so a
  # day's mix reads at a glance.
  def daily_by_service
    by_day = calls.group_by { |call| call.created_at.in_time_zone.to_date }
    top = services.first(CHART_SERVICES).map(&:service)
    parts = top.to_h { |service| [service, dates.map { |date| by_day.fetch(date, []).count { |call| call.service == service } }] }
    rest = dates.map { |date| by_day.fetch(date, []).count { |call| !top.include?(call.service) } }
    rest.any?(&:positive?) ? parts.merge(other: rest) : parts
  end

  def daily_failed
    by_day = calls.select(&:failed?).group_by { |call| call.created_at.in_time_zone.to_date }
    dates.map { |date| by_day.fetch(date, []).size }
  end

  # Busiest first, since a failure rate on a handful of calls says little.
  def services
    @services ||= calls.group_by(&:service).map do |service, of_service|
      times = of_service.filter_map(&:duration_ms)
      failures = of_service.select(&:failed?)
      ServiceRow.new(service: service, calls: of_service.size, failed: failures.size, median_ms: percentile(times, 0.5),
        p95_ms: percentile(times, 0.95), last_failure: failures.map(&:created_at).max)
    end.sort_by { |row| [-row.calls, row.service] }
  end

  def services_by_name
    @services_by_name ||= services.index_by(&:service)
  end

  def error_counts
    @error_counts ||= errors(limit: nil).to_h { |row| [[row.service, row.error], row.count] }
  end

  def daily_totals
    by_day = calls.group_by { |call| call.created_at.in_time_zone.to_date }
    dates.map { |date| by_day.fetch(date, []).size }
  end

  # The status stands in when no message came back, so a run of 429s groups
  # as one error rather than as blanks.
  def errors(limit: 10)
    calls.select(&:failed?).group_by { |call| [call.service, error_label(call)] }.map do |(service, error), failures|
      ErrorRow.new(service: service, error: error, count: failures.size, last_at: failures.map(&:created_at).max)
    end.sort_by { |row| [-row.count, row.service, row.error] }.then { |rows| rows.first(limit || rows.size) }
  end

  def to_csv
    CSV.generate do |csv|
      csv << ["Service", "Calls", "Failed", "Failure rate", "Median (ms)", "95th percentile (ms)", "Last failure"]
      compared = !previous.nil?
      services.each do |row|
        before = previous&.services_by_name&.[](row.service)
        csv << [row.service, CompareChange.cell(row.calls, before&.calls, compare: compared),
          CompareChange.cell(row.failed, before&.failed, compare: compared), row.failure_rate.round(4),
          CompareChange.cell(row.median_ms&.round, before&.median_ms&.round, compare: compared),
          CompareChange.cell(row.p95_ms&.round, before&.p95_ms&.round, compare: compared), row.last_failure&.utc&.iso8601]
      end
    end
  end

  private

  def error_label(call)
    call.error.presence&.truncate(160) || (call.status ? "HTTP #{call.status}" : "No response")
  end
end
