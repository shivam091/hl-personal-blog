# encoding: UTF-8

# The syncs run unattended on GitHub's schedule, and a failure there is only
# seen by opening the admin, so a day of them is gathered into one mail.
class SyncDigest
  PERIOD = 24.hours
  # Worded for a subject line, where "partial" alone would say little.
  PROBLEMS = {
    "failed" => "failed",
    "partial" => "with errors",
    "stalled" => "stalled"
  }.freeze
  # Enough to say what went wrong; the rest are on the sync requests page.
  ERRORS_SHOWN = 3

  attr_reader :from, :to

  def initialize(now: Time.current)
    @to = now
    @from = now - PERIOD
  end

  def requests
    @requests ||= SyncRequest.where(
      :created_at.gte => from,
      :created_at.lt => to
    ).order(created_at: :asc, _id: :asc).to_a
  end

  # By display status, so a lost run counts as stalled rather than running.
  def counts
    @counts ||= requests.map(&:display_status).tally
  end

  def problems
    requests.select { |request| PROBLEMS.key?(request.display_status) }
  end

  # A day without a single sync means the schedule itself stopped, which
  # GitHub does to a quiet repository after 60 days.
  def healthy?
    requests.any? && problems.empty?
  end

  def freshness
    SyncRequest.freshness
  end

  def summary
    return "no syncs ran in the last 24 hours" if requests.empty?
    if counts.keys == ["succeeded"]
      return (requests.one? ? "the 1 sync succeeded" : "all #{requests.size} syncs succeeded")
    end

    in_progress = counts.values_at(*SyncRequest::IN_PROGRESS).compact.sum
    parts = PROBLEMS.filter_map { |status, words| "#{counts[status]} #{words}" if counts[status] }
    parts << "#{in_progress} still running" if in_progress.positive?
    "#{parts.to_sentence} of #{requests.size}"
  end
end
