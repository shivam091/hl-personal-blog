# encoding: UTF-8

module Mixpanel
  # Daily figures rather than the events themselves: a month of raw events
  # would outgrow the database's free tier, and every report here is a
  # count, a sum or a share of them.
  class SyncService
    # Mixpanel accepts events sent up to days late (a phone back online), so
    # recent days are fetched again.
    DEFAULT_DAYS = 3
    # One export query per day against 60 an hour for the project, leaving
    # room for Mixpanel's own reports.
    MAX_DAYS = 45

    PAGE_VIEW = "$mp_web_page_view"
    PAGE_LEAVE = "page_leave"
    ISSUE_EVENTS = {"$mp_rage_click" => "rage_click", "$mp_dead_click" => "dead_click", "js_error" => "js_error"}.freeze

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(days: DEFAULT_DAYS, to: Date.current, client: Client.new, retention: RetentionService, host: Blog.host)
      @days = days.to_i.clamp(1, MAX_DAYS)
      @to = to
      @client = client
      @retention = retention
      @host = host
    end

    def call
      result = SyncResult.empty
      return result.tap { result.errors << Client::NOT_CONFIGURED } unless @client.configured?

      synced = SyncLock.hold("mixpanel") do
        ((@to - (@days - 1))..@to).each do |date|
          sync_day(date, @client.export(date).select { |event| on_blog?(event) }, result)
        rescue Client::Error => e
          result.errors << "Mixpanel #{date.iso8601}: #{e.message}"
          # A refused login or the hourly limit refuses every later day too.
          break if [401, 403, 429].include?(e.status)
        end
        # One query a run, as each cohort's later weeks fill in as it ages.
        @retention&.call(client: @client, result: result)
      end
      result.errors << "Mixpanel: another sync is already running, so this one was skipped" unless synced
      result
    end

    private

    # Only the live blog's own traffic: a local run, a preview deploy or a
    # copy of the site elsewhere sends to the same project with the same
    # token. Events without a page (the server's) are the blog's, as only
    # production sends them.
    def on_blog?(event)
      return true unless @host

      url = event.dig("properties", "$current_url").presence
      return true unless url

      URI.parse(url).host == @host
    rescue URI::InvalidURIError
      false
    end

    def sync_day(date, events, result)
      PageStat.sync(page_rows(date, events), result)
      SiteStat.sync([site_row(date, events)], result)
      IssueStat.sync(issue_rows(date, events), result)
    end

    def page_rows(date, events)
      pages = Hash.new { |hash, path| hash[path] = {date: date, page_path: path, visitors: Set.new, views: {}} }

      events.each do |event|
        # Plain clicks and the like say nothing per page, and would add a row
        # for every page clicked on without being viewed that day.
        next unless [PAGE_VIEW, PAGE_LEAVE, *ISSUE_EVENTS.keys].include?(event["event"])

        props = event["properties"] || {}
        path = path_of(props)
        next unless path

        page = pages[path]
        case event["event"]
        when PAGE_VIEW
          page[:page_views] = page[:page_views].to_i + 1
          page[:visitors] << visitor_of(props)
          page[:content_group] = props["content_group"] if props["content_group"].present?
        when PAGE_LEAVE
          # The blog resends a view's running totals each time its tab is
          # hidden, so the largest of each is the view's.
          view = page[:views][props["view_id"] || SecureRandom.uuid] ||= {seconds: 0, scroll: 0}
          view[:seconds] = [view[:seconds], props["engaged_seconds"].to_i].max
          view[:scroll] = [view[:scroll], props["max_scroll_percent"].to_i.clamp(0, 100)].max
        when *ISSUE_EVENTS.keys
          key = :"#{ISSUE_EVENTS.fetch(event["event"])}s"
          page[key] = page[key].to_i + 1
        end
      end

      pages.values.map do |page|
        views = page.delete(:views).values
        visitors = page.delete(:visitors)
        page.merge(
          visitors: visitors.size,
          engaged_views: views.size,
          engaged_seconds: views.sum { |view| view[:seconds] },
          scroll_percent_sum: views.sum { |view| view[:scroll] },
          read_through_views: views.count { |view| view[:scroll] >= PageStat::READ_THROUGH_PERCENT }
        )
      end
    end

    def site_row(date, events)
      visitors = Set.new
      ga_statuses = Hash.new { |hash, status| hash[status] = Set.new }
      themes = Hash.new { |hash, theme| hash[theme] = Set.new }
      replays = Set.new
      counts = Hash.new(0)

      events.each do |event|
        props = event["properties"] || {}
        visitor = visitor_of(props)
        visitors << visitor
        counts[event["event"]] += 1
        replays << props["$mp_replay_id"] if props["$mp_replay_id"].present?
        # Server events carry none of the browser's properties, so they'd
        # read as readers of unknown status.
        next if props["source"] == "server"

        ga_statuses[props["ga_status"].presence_in(SiteStat::GA_STATUSES) || "unknown"] << visitor
        themes[props["theme"].presence || "unknown"] << visitor
      end

      {
        date: date,
        visitors: visitors.size,
        page_views: counts[PAGE_VIEW],
        replays: replays.size,
        ga_statuses: visitor_counts(ga_statuses),
        themes: visitor_counts(themes),
        events: counts.sort_by { |name, count| [-count, name] }.map { |name, count| {"name" => name, "count" => count} },
        funnel: funnel_counts(events)
      }
    end

    def funnel_counts(events)
      did = Hash.new { |hash, step| hash[step] = Set.new }
      steps = SiteStat::FUNNEL_STEPS.transform_values(&:last)
      events.each do |event|
        steps.each { |step, names| did[step] << visitor_of(event["properties"] || {}) if names.include?(event["event"]) }
      end

      remaining = nil
      steps.keys.to_h do |step|
        remaining = remaining ? remaining & did[step] : did[step]
        [step, remaining.size]
      end
    end

    # A visitor whose early events came before the property was registered
    # (the GA check takes a few seconds) counts under what it turned out to be.
    def visitor_counts(groups)
      known = groups.except("unknown").values.reduce(Set.new, :|)
      groups["unknown"] -= known if groups.key?("unknown")
      groups.transform_values(&:size).reject { |_, count| count.zero? }
    end

    def issue_rows(date, events)
      issues = Hash.new { |hash, key| hash[key] = {count: 0, visitors: Set.new} }

      events.each do |event|
        kind = ISSUE_EVENTS[event["event"]]
        next unless kind

        props = event["properties"] || {}
        path = path_of(props) || "(unknown)"
        target = (kind == "js_error" ? error_target(props) : element_target(props)).truncate(IssueStat::MAX_TARGET)
        issue = issues[[kind, path, target]]
        issue[:count] += 1
        issue[:visitors] << visitor_of(props)
      end

      issues.map do |(kind, path, target), issue|
        {date: date, kind: kind, page_path: path, target: target, count: issue[:count], visitors: issue[:visitors].size}
      end
    end

    # The blog's own events name the path; autocaptured ones only carry the
    # URL they happened on.
    def path_of(props)
      path = props["path"].presence || begin
        URI.parse(props["$current_url"].to_s).path.presence
      rescue URI::InvalidURIError
        nil
      end
      return unless path

      path.length > 1 ? path.chomp("/") : path
    end

    def visitor_of(props)
      # The device before the id, since a subscriber's events after they're
      # identified carry a new distinct_id but the same device.
      props["$device_id"].presence || props["distinct_id"].presence || "(anonymous)"
    end

    def element_target(props)
      classes = Array(props["$el_classes"]).first(3).map { |name| ".#{name}" }.join
      id = "##{props["$el_id"]}" if props["$el_id"].present?
      element = "#{props["$el_tag_name"].presence || "element"}#{id}#{classes}"
      href = props["$el_attr__href"].presence
      href ? "#{element} → #{href}" : element
    end

    def error_target(props)
      message = props["error_message"].presence || "(no message)"
      source = props["error_source"].presence
      source ? "#{message} (#{source.split("/").last}:#{props["error_line"].to_i})" : message
    end
  end
end
