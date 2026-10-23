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
  MIN_AI_IMPRESSIONS = 20
  FAILING_RUNS = 2
  MIN_CALLS = 10
  CALL_FAILURE_RATE = 0.2

  # Past days a consent figure is judged against, and the fewest that make a usual: a week or two of
  # settled snapshots, since a tag or banner breaking shows as a step change, not a drift.
  CONSENT_BASELINE_DAYS = 14
  MIN_CONSENT_BASELINE = 5
  # Yesterday's GA-to-ours ratio below this share of the usual means GA lost views it used to keep.
  GA_RATIO_DROP = 0.7
  # In percentage points off the usual share of readers whose tag loaded, as a blocker list or a broken
  # script moves it by tens of points while ordinary days wander by a few.
  LOADED_SHARE_DROP = 0.15
  # Banners shown per pending view, below this share of the usual, means the banner has stopped appearing.
  BANNER_RATE_DROP = 0.4
  # In points above the usual share of banners left without an answer.
  NO_ANSWER_JUMP = 0.25
  # Banners a day must show before its answer rate says anything.
  MIN_BANNERS = 20

  Flag = Struct.new(:level, :icon, :title, :detail, :path, keyword_init: true)

  def initialize(today: Date.current)
    @today = today
  end

  def flags
    @flags ||= [views_flag, search_flag, ai_flag, *consent_flags, *sync_flags, *service_flags, server_errors_flag, link_safety_flag].compact
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
    # from when Google Analytics began, which the views before the blog
    # counted its own are estimated from, so the weeks before read as unknown
    # rather than as none.
    since = Google::Analytics::TrackedSince::ANALYTICS
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

  # Yesterday's reconciliation against the settled days before it, so a deploy that broke the tag or the banner
  # is flagged the next morning; none without enough snapshots to call anything usual, or enough views on the day.
  def consent_flags
    usual = ConsentSnapshot.where(:day.gte => (yesterday - CONSENT_BASELINE_DAYS).iso8601, :day.lt => yesterday.iso8601).to_a
    return [] if usual.size < MIN_CONSENT_BASELINE

    latest = ConsentSnapshot.where(day: yesterday.iso8601).first || ConsentSnapshot.compose(ConsentStats.inputs_for(yesterday, today: @today))
    path = [:consent_report_path, {from: yesterday.iso8601, to: yesterday.iso8601}]
    [ga_ratio_flag(latest, usual, path), loaded_share_flag(latest, usual, path), banner_flag(latest, usual, path), no_answer_flag(latest, usual, path)].compact
  end

  def ga_ratio_flag(latest, usual, path)
    before = median(usual.filter_map(&:ga_ratio))
    return unless latest.ga_ratio && before && latest.ga_ratio < before * GA_RATIO_DROP

    Flag.new(level: :warning, icon: "alert-triangle", title: "GA is missing more views than usual",
      detail: "GA counted #{percent(latest.ga_ratio)} of our views yesterday, against a usual #{percent(before)}.", path: path)
  end

  def loaded_share_flag(latest, usual, path)
    before = median(usual.filter_map(&:loaded_share))
    return unless latest.loaded_share && before && latest.loaded_share < before - LOADED_SHARE_DROP

    Flag.new(level: :warning, icon: "alert-triangle", title: "The GA tag is loading less often",
      detail: "It loaded for #{percent(latest.loaded_share)} of readers yesterday, against a usual #{percent(before)}.", path: path)
  end

  def banner_flag(latest, usual, path)
    before = median(usual.filter_map(&:banner_per_pending))
    return unless latest.banner_per_pending && before && latest.banner_per_pending < before * BANNER_RATE_DROP

    Flag.new(level: :warning, icon: "cookie", title: "The cookie banner is showing less",
      detail: "#{latest.shown} banners for #{latest.pending} views from readers it should ask yesterday; usually #{format("%.2f", before)} banners per such view, yesterday #{format("%.2f", latest.banner_per_pending)}.", path: path)
  end

  def no_answer_flag(latest, usual, path)
    return unless latest.shown >= MIN_BANNERS

    before = median(usual.select { |day| day.shown >= MIN_BANNERS }.map { |day| day.no_answer.fdiv(day.shown) })
    share = latest.no_answer.fdiv(latest.shown)
    return unless before && share > before + NO_ANSWER_JUMP

    Flag.new(level: :warning, icon: "cookie", title: "More banners are going unanswered",
      detail: "#{percent(share)} of banners got no answer yesterday, against a usual #{percent(before)}.", path: path)
  end

  def median(values)
    return if values.size < MIN_CONSENT_BASELINE

    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end

  def percent(value)
    "#{(value * 100).round}%"
  end

  # The latest uploaded week against the week before, both whole, since
  # uploads are made by hand and can stop short of yesterday, and a gap in
  # them would otherwise read as a drop.
  def ai_flag
    days = Google::SearchConsole::GenerativeAiSummary.new(Period.new({from: (yesterday - 60).iso8601, to: yesterday.iso8601}, today: @today)).by_date
    return if days.empty?

    latest = days.keys.max
    weeks = [(latest - 6..latest), (latest - 13..latest - 7)]
    return unless weeks.all? { |week| week.all? { |date| days.key?(date) } }

    now, before = weeks.map { |week| week.sum { |date| days[date] } }
    return if now < MIN_AI_IMPRESSIONS && before < MIN_AI_IMPRESSIONS

    detail = "#{now} AI impressions in the week to #{I18n.l(latest)}, against #{before} the week before."
    path = [:google_search_console_generative_ai_path, {from: (latest - 6).iso8601, to: latest.iso8601}]
    if before.positive? && now >= before * SPIKE
      Flag.new(level: :info, icon: "sparkles", title: "AI impressions jumped", detail: detail, path: path)
    elsif now <= before * (1 - SEARCH_DROP)
      Flag.new(level: :warning, icon: "sparkles", title: "AI impressions fell", detail: detail, path: path)
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
      path: [:search_insight_report_path, {from: (latest - 6).iso8601, to: latest.iso8601}])
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
        detail: "#{failed} of #{of_service.size} calls failed in the last 24 hours.", path: [:api_health_report_path, {}])
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
