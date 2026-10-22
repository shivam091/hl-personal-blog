# encoding: UTF-8

# Request logs read as a whole, so a rise in errors or a slow page shows
# without paging through the list. Development's own requests are left out,
# since it shares the live database and they aren't the app's traffic.
class RequestStats
  include Percentile

  STATUS_CLASSES = {"2xx" => 200..299, "3xx" => 300..399, "4xx" => 400..499, "5xx" => 500..599}.freeze
  # Clients that announce themselves as scripts or crawlers rather than
  # browsers, so a burst from one isn't read as people using the admin.
  BOT_AGENT = /bot|crawl|spider|slurp|curl|wget|python|go-http|httpclient|headless|okhttp|java\//i
  # Ids, slugs and tokens in a path, so each page is one row rather than one
  # per record opened.
  ID_SEGMENT = /\A(\d+|[0-9a-f]{24}|[0-9a-f-]{32,36}|.*%2F.*)\z/i

  Log = Struct.new(:id, :time, :path, :status, :ms, :memory_kb, :cpu, :country, :agent, :exception, keyword_init: true)
  PathRow = Struct.new(:path, :requests, :median_ms, :p95_ms, :max_ms, :errors, keyword_init: true)
  ExceptionRow = Struct.new(:name, :count, :last, keyword_init: true)

  attr_reader :period

  def initialize(period)
    @period = period
  end

  def logs
    @logs ||= RequestLog.where(created_at: period.from.in_time_zone.beginning_of_day..period.to.in_time_zone.end_of_day)
      .only(:_id, :created_at, :uri, :status, :elapsed_time, :memory_usage, :cpu_usage, :ip_info, :user_agent, :exception)
      .reject { |log| log.uri.to_s.match?(RequestLog::LOCAL_URI) }
      .map do |log|
        Log.new(id: log.id, time: log.created_at.in_time_zone, path: log.path.to_s.split("?").first, status: log.status.to_i,
          ms: log.elapsed_ms, memory_kb: log.memory_usage.to_i, cpu: log.cpu_usage.to_f, country: country_code(log.ip_info),
          agent: log.user_agent.to_s, exception: (log.exception if log.error?))
      end
  end

  def any?
    logs.any?
  end

  def total
    logs.size
  end

  def count(status_class)
    range = STATUS_CLASSES.fetch(status_class)
    logs.count { |log| range.cover?(log.status) }
  end

  def median_ms
    percentile(logs.map(&:ms), 0.5)
  end

  def p95_ms
    percentile(logs.map(&:ms), 0.95)
  end

  def dates
    (period.from..period.to).to_a
  end

  # Zero-filled, so a quiet day reads as one rather than being skipped.
  def daily_by_status
    by_day = logs.group_by { |log| log.time.to_date }
    STATUS_CLASSES.transform_values do |range|
      dates.map { |date| by_day.fetch(date, []).count { |log| range.cover?(log.status) } }
    end
  end

  # Nil on a day without requests, so the line breaks rather than dropping
  # to a time of nothing.
  def daily_timings
    by_day = logs.group_by { |log| log.time.to_date }.transform_values { |day| day.map(&:ms) }
    {median: dates.map { |date| percentile(by_day[date], 0.5)&.round }, p95: dates.map { |date| percentile(by_day[date], 0.95)&.round }}
  end

  # The 95th percentile first, as the slow tail is what a reader waits on;
  # a page's median alone hides it.
  def slowest_paths(limit: 10)
    rows = logs.group_by { |log| path_pattern(log.path) }.map do |path, hits|
      times = hits.map(&:ms)
      PathRow.new(path: path, requests: hits.size, median_ms: percentile(times, 0.5), p95_ms: percentile(times, 0.95), max_ms: times.max,
        errors: hits.count { |log| log.status >= 500 })
    end.sort_by { |row| [-row.p95_ms, row.path] }
    rows.first(limit || rows.size)
  end

  # Grouped by class, as the message often carries an id that differs every
  # time; the latest one is linked so its backtrace is a click away.
  def exceptions(limit: 10)
    logs.select(&:exception).group_by { |log| log.exception["class"] }.map do |name, hits|
      ExceptionRow.new(name: name, count: hits.size, last: hits.max_by(&:time))
    end.sort_by { |row| [-row.count, row.name] }.first(limit)
  end

  def countries
    logs.each_with_object(Hash.new(0)) { |log, counts| counts[log.country] += 1 }
  end

  def agents
    logs.each_with_object(Hash.new(0)) { |log, counts| counts[agent_label(log.agent)] += 1 }
  end

  def bots
    logs.count { |log| log.agent.blank? || log.agent.match?(BOT_AGENT) }
  end

  # Weekday rows from Monday and hour columns in the app's time zone, so a
  # cell is when the admin was actually being used.
  def hours
    cells = Array.new(7) { Array.new(24, 0) }
    logs.each { |log| cells[log.time.to_date.cwday - 1][log.time.hour] += 1 }
    cells
  end

  # The highest a day reached rather than its average, since memory that
  # climbs and stays up is what gets a process restarted.
  def daily_memory_mb
    by_day = logs.group_by { |log| log.time.to_date }
    dates.map { |date| (by_day[date]&.map(&:memory_kb)&.max.to_f / 1024).round if by_day[date] }
  end

  def daily_cpu
    by_day = logs.group_by { |log| log.time.to_date }
    dates.map { |date| (by_day[date].sum(&:cpu) / by_day[date].size).round(1) if by_day[date] }
  end

  # A row per page rather than per request, as the log itself can already
  # be read request by request.
  def to_csv
    CSV.generate do |csv|
      csv << ["Path", "Requests", "Median (ms)", "95th percentile (ms)", "Slowest (ms)", "Server errors"]
      slowest_paths(limit: nil).each do |row|
        csv << [row.path, row.requests, row.median_ms&.round, row.p95_ms&.round, row.max_ms&.round, row.errors]
      end
    end
  end

  private

  def path_pattern(path)
    segments = path.split("/").map { |segment| segment.match?(ID_SEGMENT) ? ":id" : segment }
    segments.join("/").presence || "/"
  end

  def country_code(info)
    code = info.to_h["country_code"].to_s
    code.match?(/\A[A-Za-z]{2}\z/) ? code.upcase : BlogStats::UNKNOWN_COUNTRY
  end

  # Browser and system rather than the whole string, which differs with
  # every version and would leave no two rows alike.
  def agent_label(agent)
    return "No user agent" if agent.blank?
    return agent.split(%r{[/ ;(]}).first.presence || "Other client" if agent.match?(BOT_AGENT) || !agent.start_with?("Mozilla")

    browser = case agent
    when /Edg\//i then "Edge"
    when /Firefox\//i then "Firefox"
    when /Chrome\//i then "Chrome"
    when /Safari\//i then "Safari"
    else "Other browser"
    end
    system = case agent
    when /Android/i then "Android"
    when /iPhone|iPad/i then "iOS"
    when /Mac OS X/i then "macOS"
    when /Windows/i then "Windows"
    when /Linux/i then "Linux"
    else "Other"
    end
    "#{browser} on #{system}"
  end
end
