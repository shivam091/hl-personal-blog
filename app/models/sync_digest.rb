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
  # Enough to say what went wrong without a long mail.
  ERRORS_SHOWN = 3
  # Weeks before the last one whose shares make the usual: a month, so one odd week can't set it.
  USUAL_WEEKS = 4

  # GA's share of our views over the last full week, beside the usual week's, so a fall in GA's numbers
  # can be told from readers it no longer sees.
  GaShare = Struct.new(:last_week, :usual, keyword_init: true)

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
    requests.any? && problems.empty? && missing_snapshot.nil?
  end

  # A night the snapshot job didn't run leaves no request to list, only a day without a snapshot.
  def missing_snapshot
    return @missing_snapshot if defined?(@missing_snapshot)

    @missing_snapshot = ConsentSnapshotCheck.new(today: to.to_date).missing_day
  end

  def freshness
    SyncRequest.freshness
  end

  # The Generative AI report is exported and uploaded by hand, so nothing fails when it goes stale; the mail
  # asks for it again until it's done. Not a sync, so it leaves the syncs' verdict alone.
  def stale_ai_upload
    return @stale_ai_upload if defined?(@stale_ai_upload)

    ai = Google::SearchConsole::GenerativeAiSummary.new(Period.new({}, today: to.to_date))
    @stale_ai_upload = (ai if ai.stale?(today: to.to_date))
  end

  def needs_a_look?
    problems.any? || missing_snapshot.present? || stale_ai_upload.present?
  end

  # Nil unless both are known. The usual is the median of earlier weeks' shares, worked out the same way
  # as last week's, rather than ConsentSnapshot.usual(:ga_ratio), whose median of single days weighs a quiet
  # Sunday like a busy Tuesday and draws on days within last week itself.
  def ga_share
    return @ga_share if defined?(@ga_share)

    last = to.to_date - 1
    @ga_share = begin
      latest = ConsentSnapshot.ga_share(week_ending(last))
      earlier = (1..USUAL_WEEKS).filter_map { |weeks| ConsentSnapshot.ga_share(week_ending(last - (weeks * 7))) }
      GaShare.new(last_week: latest, usual: median(earlier)) if latest && earlier.size >= Anomalies::MIN_WEEKS
    end
  end

  def summary
    return sync_summary unless missing_snapshot

    "#{sync_summary}, and no consent snapshot for #{I18n.l(missing_snapshot, format: :short)}"
  end

  private

  def week_ending(day)
    Period.new({from: (day - 6).iso8601, to: day.iso8601})
  end

  def median(values)
    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  def sync_summary
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
