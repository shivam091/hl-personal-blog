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
    CLICK = "$mp_click"
    SUBSCRIBE = "newsletter_subscribe"
    ISSUE_EVENTS = {"$mp_rage_click" => "rage_click", "$mp_dead_click" => "dead_click", "js_error" => "js_error"}.freeze
    # Enough to watch a moment or a reading without the stored row growing
    # with every session recorded.
    MAX_REPLAYS = 3

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
      traits = visitor_traits(events)
      pages = page_rows(date, events, traits)
      PageStat.sync(pages, result)
      SiteStat.sync([site_row(date, events, traits)], result)
      IssueStat.sync(issue_rows(date, events), result)
      sync_clicks(date, click_rows(date, events, pages), result)
    end

    # Per visitor rather than per event, since the blog registers these a
    # few seconds into a visit and the first page view goes out without them.
    def visitor_traits(events)
      traits = Hash.new { |hash, visitor| hash[visitor] = {} }
      events.each do |event|
        props = event["properties"] || {}
        next if props["source"] == "server"

        trait = traits[visitor_of(props)]
        status = props["ga_status"].presence_in(SiteStat::GA_STATUSES)
        trait[:ga_status] = status if status && status != "unknown"
        trait[:reduced_motion] = flag(props["prefers_reduced_motion"]) unless props["prefers_reduced_motion"].nil?
        trait[:prefers_dark] = flag(props["prefers_dark"]) unless props["prefers_dark"].nil?
      end
      traits
    end

    def flag(value)
      ActiveModel::Type::Boolean.new.cast(value)
    end

    def page_rows(date, events, traits)
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
          view[:replay] ||= replay_of(props)
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
          read_through_views: views.count { |view| view[:scroll] >= PageStat::READ_THROUGH_PERCENT },
          ga_statuses: visitors.map { |visitor| traits.dig(visitor, :ga_status) || "unknown" }.tally,
          scroll_reached: PageStat::SCROLL_MILESTONES.to_h { |percent| [percent.to_s, views.count { |view| view[:scroll] >= percent }] },
          reading_times: views.map { |view| PageStat.reading_time(view[:seconds]) }.tally,
          # The longest readings, since a replay of a bounce shows little.
          replays: views.select { |view| view[:replay] }.sort_by { |view| -view[:seconds] }
            .map { |view| view[:replay].merge("seconds" => view[:seconds]) }.uniq { |replay| replay["replay_id"] }.first(MAX_REPLAYS)
        )
      end
    end

    # Only for pages read enough that day for their top few to mean
    # something, which keeps the collection to a few rows a page.
    def click_rows(date, events, pages)
      busy = pages.select { |page| page[:page_views].to_i >= ClickStat::MIN_PAGE_VIEWS }.to_set { |page| page[:page_path] }
      clicks = Hash.new { |hash, key| hash[key] = {count: 0, visitors: Set.new} }

      events.each do |event|
        next unless event["event"] == CLICK

        props = event["properties"] || {}
        path = path_of(props)
        next unless busy.include?(path)

        click = clicks[[path, element_target(props).truncate(ClickStat::MAX_TARGET)]]
        click[:count] += 1
        click[:visitors] << visitor_of(props)
      end

      clicks.group_by { |(path, _), _| path }.flat_map do |path, rows|
        rows.sort_by { |(_, target), click| [-click[:count], target] }.first(ClickStat::TOP).map do |(_, target), click|
          {date: date, page_path: path, target: target, count: click[:count], visitors: click[:visitors].size}
        end
      end
    end

    # A day synced again can rank other elements in its top few, and the
    # ones that dropped out would otherwise stay counted beside them.
    def sync_clicks(date, rows, result)
      kept = rows.to_set { |row| [row[:page_path], row[:target]] }
      ClickStat.where(date: date).each { |stat| stat.destroy unless kept.include?([stat.page_path, stat.target]) }
      ClickStat.sync(rows, result)
    end

    def site_row(date, events, traits)
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
        funnel: funnel_counts(events),
        reduced_motion: preference_counts(traits, :reduced_motion, "reduce", "no_preference"),
        color_schemes: preference_counts(traits, :prefers_dark, "dark", "light"),
        form_steps: form_step_counts(events),
        form_errors: form_error_counts(events),
        **subscriber_journey(events)
      }
    end

    def preference_counts(traits, key, yes, no)
      traits.values.filter_map { |trait| (trait[key] ? yes : no) unless trait[key].nil? }.tally
    end

    # Each step on its own rather than narrowed like the funnel, since an
    # error is a branch off submitting, not a step after it.
    def form_step_counts(events)
      steps = SiteStat::FORM_STEPS.transform_values(&:last)
      did = Hash.new { |hash, step| hash[step] = Set.new }
      events.each do |event|
        steps.each { |step, name| did[step] << visitor_of(event["properties"] || {}) if name == event["event"] }
      end
      did.transform_values(&:size)
    end

    def form_error_counts(events)
      events.filter_map { |event| (event["properties"] || {})["error_message"].presence if event["event"] == "newsletter_form_error" }
        .tally.sort_by { |message, count| [-count, message] }.map { |message, count| {"message" => message, "count" => count} }
    end

    # By device rather than id for the reads before, since the reader is
    # only named from the subscribe on; by id for returns, since a later
    # visit may come from another device.
    def subscriber_journey(events)
      subscribed_at = {}
      new_ids = Set.new
      events.each do |event|
        next unless event["event"] == SUBSCRIBE

        props = event["properties"] || {}
        id = reader_of(props)
        new_ids << id if id
        device = visitor_of(props)
        subscribed_at[device] = [subscribed_at[device], time_of(props)].compact.max
      end

      reads = Hash.new(0)
      returning = Hash.new(0)
      events.each do |event|
        next unless event["event"] == PAGE_VIEW

        props = event["properties"] || {}
        at = subscribed_at[visitor_of(props)]
        path = path_of(props)
        reads[path] += 1 if at && path && time_of(props).to_i <= at
        id = reader_of(props)
        # A subscriber's pages right after subscribing are the same visit, not a return.
        returning[id] += 1 if id && !new_ids.include?(id)
      end

      {
        new_subscribers: new_ids.to_a.sort,
        subscriber_reads: reads.sort_by { |path, count| [-count, path] }.map { |path, count| {"path" => path, "count" => count} },
        returning_subscribers: returning.sort.map { |id, views| {"id" => id, "page_views" => views} }
      }
    end

    def reader_of(props)
      id = props["$user_id"].presence || props["distinct_id"].to_s
      id if id.start_with?(SiteStat::READER_PREFIX)
    end

    # The server sends milliseconds and the browser seconds.
    def time_of(props)
      time = props["time"]
      return unless time.is_a?(Numeric)

      time > 100_000_000_000 ? time / 1000 : time
    end

    def replay_of(props)
      id = props["$mp_replay_id"].presence
      {"replay_id" => id, "distinct_id" => props["distinct_id"].to_s, "time" => time_of(props)&.to_i} if id
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
      issues = Hash.new { |hash, key| hash[key] = {count: 0, visitors: Set.new, replays: []} }

      events.each do |event|
        kind = ISSUE_EVENTS[event["event"]]
        next unless kind

        props = event["properties"] || {}
        path = path_of(props) || "(unknown)"
        target = (kind == "js_error" ? error_target(props) : element_target(props)).truncate(IssueStat::MAX_TARGET)
        issue = issues[[kind, path, target]]
        issue[:count] += 1
        issue[:visitors] << visitor_of(props)
        replay = replay_of(props)
        issue[:replays] << replay if replay && issue[:replays].size < MAX_REPLAYS && issue[:replays].none? { |seen| seen["replay_id"] == replay["replay_id"] }
      end

      issues.map do |(kind, path, target), issue|
        {date: date, kind: kind, page_path: path, target: target, count: issue[:count], visitors: issue[:visitors].size, replays: issue[:replays]}
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
