# encoding: UTF-8

# Sync requests read as a whole, so a kind that keeps failing or slowing
# down shows before its pages go stale.
class SyncStats
  include Percentile

  # Outcomes in the order a run can end, so a day's bar reads from good at
  # the base to bad at the top.
  OUTCOMES = %w[succeeded partial failed stalled in_progress].freeze

  KindRow = Struct.new(:kind, :section, :runs, :outcomes, :median_seconds, :max_seconds, :rows, :failing_streak, :last_success,
    keyword_init: true) do
    def finished
      outcomes.values_at("succeeded", "partial", "failed").sum
    end

    # Of finished runs only, so one still going doesn't count against it.
    def success_rate
      outcomes.values_at("succeeded", "partial").sum.fdiv(finished) if finished.positive?
    end
  end
  ErrorRow = Struct.new(:message, :count, :kinds, :last_at, keyword_init: true)

  attr_reader :period

  def initialize(period)
    @period = period
  end

  def requests
    @requests ||= SyncRequest.where(created_at: period.from.in_time_zone.beginning_of_day..period.to.in_time_zone.end_of_day)
      .order(created_at: :asc).to_a
  end

  def any?
    requests.any?
  end

  def total
    requests.size
  end

  def outcome_counts
    requests.each_with_object(OUTCOMES.index_with(0)) { |request, counts| counts[outcome(request)] += 1 }
  end

  def dates
    (period.from..period.to).to_a
  end

  def daily_by_outcome
    by_day = requests.group_by { |request| request.created_at.in_time_zone.to_date }
    OUTCOMES.index_with { |name| dates.map { |date| by_day.fetch(date, []).count { |request| outcome(request) == name } } }
  end

  # Created and updated only, since unchanged rows are a sync finding
  # nothing new.
  def daily_rows
    by_day = requests.group_by { |request| request.created_at.in_time_zone.to_date }
    dates.map { |date| by_day.fetch(date, []).sum { |request| request.created_count.to_i + request.updated_count.to_i } }
  end

  # Every kind, even one not run in the period, since a kind that never
  # runs is as much a problem as one that fails.
  def kinds
    by_kind = requests.group_by(&:kind)
    SyncRequest::KINDS.values.map do |info|
      runs = by_kind.fetch(info.key, [])
      times = runs.filter_map(&:duration)
      KindRow.new(
        kind: info.key,
        section: info.section,
        runs: runs.size,
        outcomes: runs.each_with_object(OUTCOMES.index_with(0)) { |request, counts| counts[outcome(request)] += 1 },
        median_seconds: percentile(times, 0.5),
        max_seconds: times.max,
        rows: runs.sum { |request| request.created_count.to_i + request.updated_count.to_i },
        failing_streak: runs.reverse.reject { |request| outcome(request) == "in_progress" }.take_while { |request| outcome(request) == "failed" }.size,
        last_success: SyncRequest.last_completed(info.key)&.finished_at
      )
    end.sort_by { |row| [-row.failing_streak, -row.runs, row.section] }
  end

  # URLs and numbers stripped, so the same failure on another page, day or
  # row groups as one rather than one per occurrence.
  def errors(limit: 10)
    requests.flat_map { |request| request.error_messages.map { |message| [error_pattern(message), request] } }
      .group_by(&:first).map do |message, pairs|
        runs = pairs.map(&:last)
        ErrorRow.new(message: message, count: pairs.size, kinds: runs.map(&:section).uniq.sort, last_at: runs.map(&:created_at).max)
      end.sort_by { |row| [-row.count, row.message] }.first(limit)
  end

  def to_csv
    CSV.generate do |csv|
      csv << ["Sync", "Kind", "Runs", *OUTCOMES.map(&:humanize), "Median (s)", "Longest (s)", "Rows created or updated", "Failed in a row",
        "Last success"]
      kinds.each do |row|
        csv << [row.section, row.kind, row.runs, *row.outcomes.values_at(*OUTCOMES), row.median_seconds&.round, row.max_seconds&.round,
          row.rows, row.failing_streak, row.last_success&.utc&.iso8601]
      end
    end
  end

  private

  def error_pattern(message)
    message.to_s.gsub(%r{https?://\S+?(?=:?\s|:?\z)}, "URL").gsub(/\d+/, "#").truncate(200)
  end

  def outcome(request)
    status = request.display_status
    SyncRequest::IN_PROGRESS.include?(status) ? "in_progress" : status
  end
end
