# encoding: UTF-8

# What's out of the ordinary right now, whatever period the dashboard shows,
# so a drop, a spike or a failure is seen the day it happens rather than
# when someone thinks to look.
class Anomalies
  # Weeks of the same weekday a day is judged against, since traffic swings
  # by weekday and a Monday read against a Sunday would always look odd.
  WEEKS_BACK = 4
  # One week back is a single day to judge by, too few to call usual.
  MIN_WEEKS = 2
  SPIKE = 2.0
  DROP = 0.5
  # Below these, a doubling or halving is a handful of views or clicks.
  MIN_VIEWS = 10
  MIN_CLICKS = 20
  SEARCH_DROP = 0.4
  FAILING_RUNS = 2
  MIN_CALLS = 10
  CALL_FAILURE_RATE = 0.2

  Flag = Struct.new(:level, :icon, :title, :detail, :path, keyword_init: true)

  def initialize(today: Date.current)
    @today = today
  end

  def flags
    @flags ||= [views_flag, search_flag, *sync_flags, *service_flags, server_errors_flag, link_safety_flag].compact
  end

  def any?
    flags.any?
  end

  private

  def yesterday
    @today - 1
  end

  def views_flag
    stats = BlogStats.new(Period.new({from: (yesterday - WEEKS_BACK * 7).iso8601, to: yesterday.iso8601}, today: @today))
    daily = stats.daily(:views)
    latest = daily.last
    # The same weekday in each earlier week, every seventh day back, but only
    # from when views were counted, so the weeks before read as unknown
    # rather than as none.
    since = stats.views_counted_since
    weeks = (1..WEEKS_BACK).select { |back| since && yesterday - back * 7 >= since }
    return if weeks.size < MIN_WEEKS

    usual = weeks.sum { |back| daily[-1 - back * 7] }.fdiv(weeks.size)
    return if usual < MIN_VIEWS && latest < MIN_VIEWS

    weekday = I18n.l(yesterday, format: "%A")
    if latest >= usual * SPIKE
      Flag.new(level: :info, icon: "trending-up", title: "Views spiked yesterday",
        detail: "#{latest} views against a usual #{usual.round} on a #{weekday}.", path: [:page_views_path, {from: yesterday.iso8601, to: yesterday.iso8601}])
    elsif latest <= usual * DROP
      Flag.new(level: :warning, icon: "arrow-down", title: "Views dropped yesterday",
        detail: "#{latest} views against a usual #{usual.round} on a #{weekday}.", path: [:page_views_path, {from: yesterday.iso8601, to: yesterday.iso8601}])
    end
  end

  # The latest synced week, since Search Console fills in recent days late
  # and a week cut short would always read as a drop.
  def search_flag
    totals = Google::SearchConsole::Stat.grouped(Google::SearchConsole::Stat.site_totals.where(:date.gte => yesterday - 60), by: [:date])
      .to_h { |row| [row.date, row.clicks] }
    return if totals.empty?

    latest = totals.keys.max
    now = (latest - 6..latest).sum { |date| totals.fetch(date, 0) }
    before = (latest - 13..latest - 7).sum { |date| totals.fetch(date, 0) }
    return if before < MIN_CLICKS || now > before * (1 - SEARCH_DROP)

    Flag.new(level: :warning, icon: "search", title: "Search clicks fell",
      detail: "#{now} clicks in the week to #{I18n.l(latest)}, down from #{before} the week before.",
      path: [:search_report_path, {from: (latest - 6).iso8601, to: latest.iso8601}])
  end

  def sync_flags
    SyncRequest::KINDS.values.filter_map do |info|
      finished = SyncRequest.where(kind: info.key, :status.in => %w[succeeded partial failed]).order(finished_at: :desc).limit(FAILING_RUNS).pluck(:status)
      next unless finished.size == FAILING_RUNS && finished.all?("failed")

      Flag.new(level: :warning, icon: "refresh", title: "#{info.section} sync keeps failing",
        detail: "Its last #{FAILING_RUNS} runs failed.", path: [:sync_requests_path, {section: info.key}])
    end
  end

  def service_flags
    calls = ExternalCall.where(:created_at.gte => 24.hours.ago).only(:service, :status).to_a
    calls.group_by(&:service).filter_map do |service, of_service|
      failed = of_service.count(&:failed?)
      next if of_service.size < MIN_CALLS || failed.fdiv(of_service.size) < CALL_FAILURE_RATE

      Flag.new(level: :warning, icon: "send", title: "#{service} is failing",
        detail: "#{failed} of #{of_service.size} calls failed in the last 24 hours.", path: [:external_call_report_path, {}])
    end
  end

  # Development's own requests left out, as it shares the live database.
  def server_errors_flag
    count = RequestLog.where(:created_at.gte => 24.hours.ago, :status.gte => 500).pluck(:uri).count { |uri| !uri.to_s.match?(RequestLog::LOCAL_URI) }
    return if count.zero?

    Flag.new(level: :warning, icon: "alert-triangle", title: "Server errors",
      detail: "#{count} #{"request".pluralize(count)} failed with a 5xx status in the last 24 hours.", path: [:request_report_path, {}])
  end

  def link_safety_flag
    count = Google::SafeBrowsing::LinkCheck.flagged.count
    return if count.zero?

    Flag.new(level: :warning, icon: "shield-alert", title: "Unsafe outbound links",
      detail: "Safe Browsing lists #{count} #{"link".pluralize(count)} readers followed out of the blog.", path: [:google_safe_browsing_link_checks_path, {}])
  end
end
