# encoding: UTF-8

module Mixpanel
  # Added up in Ruby rather than aggregated in Mongo: a period is at most a
  # few thousand small rows, and the figures need sets of rows the database
  # would have to be asked for one by one.
  class Report
    Page = Struct.new(:page_path, :content_group, :page_views, :visitors, :engaged_views, :engaged_seconds, :scroll_percent_sum,
      :read_through_views, :rage_clicks, :dead_clicks, :js_errors, :ga_statuses, :scroll_reached, :reading_times, :replays,
      keyword_init: true) do
      def mean_engaged_seconds
        engaged_seconds.fdiv(engaged_views) if engaged_views.positive?
      end

      def mean_scroll_share
        scroll_percent_sum.fdiv(engaged_views * 100) if engaged_views.positive?
      end

      def read_through_share
        read_through_views.fdiv(engaged_views) if engaged_views.positive?
      end

      def frustrations
        rage_clicks + dead_clicks + js_errors
      end

      # Blocked and never-started alike, since GA sees neither; readers
      # whose status never arrived are left out of both sides.
      def ga_unseen_share
        known = ga_statuses.except("unknown").values.sum
        (ga_statuses["blocked"].to_i + ga_statuses["off"].to_i).fdiv(known) if known.positive?
      end

      # A factor rather than a share, so GA's own figure can be corrected
      # as it stands.
      def ga_correction
        share = ga_unseen_share
        1 / (1 - share) if share && share < 1
      end

      # Out of every view, a bounce counted as reaching nothing, so a page
      # left at once doesn't look well read.
      def scroll_reached_share(percent)
        base = [page_views, engaged_views].max
        scroll_reached[percent.to_s].to_i.fdiv(base) if base.positive?
      end

      # A view with no time and no scroll sends nothing, so it joins the
      # shortest bucket here.
      def reading_time_counts
        bounces = [page_views - engaged_views, 0].max
        PageStat::READING_TIMES.keys.map { |key| reading_times[key].to_i + (key == PageStat::READING_TIMES.keys.first ? bounces : 0) }
      end
    end

    Issue = Struct.new(:kind, :page_path, :target, :count, :visitors, :replays, keyword_init: true)
    Click = Struct.new(:page_path, :target, :count, :visitors, keyword_init: true)
    Journey = Struct.new(:subscribers, :reads, :came_back, :return_days, :returning, :return_page_views, keyword_init: true) do
      def came_back_share
        came_back.fdiv(subscribers) if subscribers.positive?
      end

      def mean_return_days
        return_days.fdiv(came_back) if came_back.positive?
      end
    end

    SUMMED = %i[page_views visitors engaged_views engaged_seconds scroll_percent_sum read_through_views rage_clicks dead_clicks js_errors].freeze
    TALLIED = %i[ga_statuses scroll_reached reading_times].freeze

    attr_reader :period

    def initialize(period)
      @period = period
    end

    def any?
      SiteStat.exists?
    end

    # Nil without a comparison, or before anything was synced for it, so the
    # first synced period isn't set against nothing as if it were a collapse.
    def previous
      return @previous if defined?(@previous)

      # Mixpanel's figures aren't split by country, so another country's
      # would be these same figures.
      @previous = (Report.new(period.previous) if period.compare? && !period.compare_countries? && SiteStat.where(:date.lte => period.previous.to).exists?)
    end

    def dates
      @dates ||= (period.from..period.to).to_a
    end

    # A figure for each day of the period, nil on a day never synced so it
    # isn't drawn as a real zero.
    def site_daily(field = nil, &block)
      block ||= ->(day) { day.public_send(field) }
      by_date = days.index_by(&:date)
      dates.map { |date| (day = by_date[date]) && block.(day) }
    end

    def ga_daily(status)
      site_daily { |day| day.ga_statuses[status].to_i }
    end

    # A synced day with no row for the page is a day nobody read it.
    def page_daily(field, path: nil)
      rows = path ? page_rows.select { |row| row.page_path == path } : page_rows
      sums = rows.group_by(&:date).transform_values { |group| group.sum(&field) }
      synced = days.to_set(&:date)
      dates.map { |date| sums.fetch(date, 0) if synced.include?(date) }
    end

    # Divided per bucket rather than averaged per day, so a quiet day weighs
    # no more than a busy one.
    def ratios(granularity, numerator, denominator, scale: 1)
      numerators, denominators = yield(numerator), yield(denominator)
      granularity.sums(dates, numerators).zip(granularity.sums(dates, denominators)).map do |top, bottom|
        (top.to_f * scale / bottom).round(1) if top && bottom&.positive?
      end
    end

    def mean_engaged_seconds_by(granularity, path: nil)
      ratios(granularity, :engaged_seconds, :engaged_views) { |field| page_daily(field, path: path) }
    end

    def read_through_percent_by(granularity, path: nil)
      ratios(granularity, :read_through_views, :engaged_views, scale: 100) { |field| page_daily(field, path: path) }
    end

    def mean_scroll_percent_by(granularity, path: nil)
      ratios(granularity, :scroll_percent_sum, :engaged_views) { |field| page_daily(field, path: path) }
    end

    def blocked_percent_by(granularity)
      ratios(granularity, "blocked", :all, scale: 100) do |status|
        status == :all ? site_daily { |day| day.ga_statuses.values.sum(&:to_i) } : ga_daily(status)
      end
    end

    # Daily, for a sparkline: nil on unsynced days and days without a base.
    def daily_ratio(numerator, denominator, scale: 1, path: nil)
      page_daily(numerator, path: path).zip(page_daily(denominator, path: path)).map do |top, bottom|
        (top.to_f * scale / bottom).round(1) if top && bottom&.positive?
      end
    end

    def days
      @days ||= period.apply(SiteStat.all).order(date: :asc).to_a
    end

    # Summed day by day, so a reader on two days counts twice, as GA's daily
    # user figures add up.
    def visitors
      days.sum(&:visitors)
    end

    def page_views
      days.sum(&:page_views)
    end

    def replays
      days.sum(&:replays)
    end

    def site
      @site ||= Page.new(page_path: "(all)", **SUMMED.index_with { |field| pages.sum(&field) }, **TALLIED.index_with { |field| tally(pages, field) },
        replays: [])
    end

    def page_rows
      @page_rows ||= period.apply(PageStat.all).to_a
    end

    def pages
      @pages ||= page_rows.group_by(&:page_path).map do |path, rows|
        Page.new(page_path: path, content_group: rows.filter_map(&:content_group).last, **SUMMED.index_with { |field| rows.sum(&field) },
          **TALLIED.index_with { |field| tally(rows, field) }, replays: longest_replays(rows.flat_map(&:replays)))
      end
    end

    def page(path)
      @pages_by_path ||= pages.index_by(&:page_path)
      @pages_by_path[path]
    end

    def top_pages(limit: 25)
      rows = pages.select { |page| page.page_views.positive? }.sort_by { |page| [-page.page_views, page.page_path] }
      limit ? rows.first(limit) : rows
    end

    # Pages readers leave early, among those read often enough to judge.
    def least_read_pages(min_views: 10, limit: 10)
      pages.select { |page| page.engaged_views >= min_views }.sort_by { |page| [page.read_through_share, page.page_path] }.first(limit)
    end

    def issues(kind, limit: 15)
      rows = period.apply(IssueStat.where(kind: kind)).to_a.group_by { |row| [row.page_path, row.target] }.map do |(path, target), group|
        # The latest first, since Mixpanel deletes replays after a while.
        replays = group.sort_by(&:date).reverse.flat_map(&:replays).uniq { |replay| replay["replay_id"] }.first(SyncService::MAX_REPLAYS)
        Issue.new(kind: kind, page_path: path, target: target, count: group.sum(&:count), visitors: group.sum(&:visitors), replays: replays)
      end
      rows.sort_by { |issue| [-issue.count, issue.page_path, issue.target] }.first(limit)
    end

    # Pages whose GA coverage differs enough to matter, among those with
    # enough known readers to judge.
    def ga_coverage_pages(min_visitors: 10, limit: 15)
      pages.select { |page| page.ga_statuses.except("unknown").values.sum >= min_visitors }
        .sort_by { |page| [-page.ga_unseen_share, page.page_path] }.first(limit)
    end

    def click_rows
      @click_rows ||= period.apply(ClickStat.all).to_a
    end

    def clicks(path, limit: ClickStat::TOP)
      @clicks ||= click_rows.group_by(&:page_path).transform_values do |rows|
        rows.group_by(&:target).map do |target, group|
          Click.new(page_path: group.first.page_path, target: target, count: group.sum(&:count), visitors: group.sum(&:visitors))
        end.sort_by { |click| [-click.count, click.target] }
      end
      @clicks.fetch(path, []).first(limit)
    end

    # The most read pages that have any, so the busiest come first.
    def clicked_pages(limit: 10)
      paths = click_rows.to_set(&:page_path)
      top_pages(limit: nil).select { |page| paths.include?(page.page_path) }.first(limit)
    end

    def reduced_motion_shares
      shares_of(:reduced_motion)
    end

    def color_scheme_shares
      shares_of(:color_schemes)
    end

    # Labelled steps, nil before any day carried one.
    def form_steps
      return unless days.any? { |day| day.form_steps.present? }

      SiteStat::FORM_STEPS.map { |step, (label, _)| [step, label, days.sum { |day| day.form_steps[step].to_i }] }
    end

    def form_errors
      counts = Hash.new(0)
      days.each { |day| day.form_errors.each { |row| counts[row["message"]] += row["count"].to_i } }
      counts.sort_by { |message, count| [-count, message] }
    end

    # The period's new subscribers are followed past its end, since a return
    # can only come after the subscribe; today is as far as anyone has got.
    def subscriber_journey(limit: 10)
      return unless days.any? { |day| day.new_subscribers.present? || day.returning_subscribers.present? }

      first_seen = {}
      days.each { |day| day.new_subscribers.each { |id| first_seen[id] ||= day.date } }
      later = SiteStat.where(:date.gt => period.from).only(:date, :returning_subscribers).to_a
      return_days = first_seen.to_h do |id, date|
        [id, later.count { |day| day.date > date && day.returning_subscribers.any? { |row| row["id"] == id } }]
      end

      reads = Hash.new(0)
      days.each { |day| day.subscriber_reads.each { |row| reads[row["path"]] += row["count"].to_i } }
      returning = days.flat_map(&:returning_subscribers)

      Journey.new(
        subscribers: first_seen.size,
        reads: reads.sort_by { |path, count| [-count, path] }.first(limit),
        came_back: return_days.values.count(&:positive?),
        return_days: return_days.values.sum,
        returning: returning.map { |row| row["id"] }.uniq.size,
        return_page_views: returning.sum { |row| row["page_views"].to_i }
      )
    end

    # Each status's share of the readers Mixpanel saw: the blocked share is
    # the part of the audience absent from every GA report.
    def ga_shares
      shares_of(:ga_statuses)
    end

    def theme_shares
      shares_of(:themes)
    end

    # Labelled steps for funnel_chart, nil before any day carried one.
    def funnel
      return unless days.any? { |day| day.funnel.present? }

      SiteStat::FUNNEL_STEPS.map { |step, (label, _)| [label, days.sum { |day| day.funnel[step].to_i }] }
    end

    # The latest cohorts Mixpanel reported, whatever the period, since a
    # cohort's later weeks only exist once it has aged.
    def cohorts
      @cohorts ||= RetentionCohort.where(:cohort_date.gte => Date.current - RetentionService::WEEKS * 7).order(cohort_date: :asc).to_a
    end

    def events
      counts = Hash.new(0)
      days.each { |day| day.events.each { |row| counts[row["name"]] += row["count"].to_i } }
      counts.sort_by { |name, count| [-count, name] }
    end

    def to_csv
      milestones = PageStat::SCROLL_MILESTONES
      CSV.generate do |csv|
        csv << ["Page path", "Content group", "Page views", "Visitors", "Engaged views", "Mean engaged seconds", "Mean scroll depth",
          "Read-through share", "Rage clicks", "Dead clicks", "Script errors", "GA unseen share",
          *milestones.map { |percent| "Reached #{percent}%" }, *PageStat::READING_TIMES.values.map(&:first)]
        top_pages(limit: nil).each do |page|
          csv << [page.page_path, page.content_group, page.page_views, page.visitors, page.engaged_views, page.mean_engaged_seconds&.round(1),
            page.mean_scroll_share&.round(4), page.read_through_share&.round(4), page.rage_clicks, page.dead_clicks, page.js_errors,
            page.ga_unseen_share&.round(4), *milestones.map { |percent| page.scroll_reached_share(percent)&.round(4) }, *page.reading_time_counts]
        end
      end
    end

    private

    def tally(rows, field)
      rows.each_with_object(Hash.new(0)) { |row, sums| row.public_send(field).each { |key, count| sums[key] += count.to_i } }
    end

    def longest_replays(replays)
      replays.sort_by { |replay| -replay["seconds"].to_i }.uniq { |replay| replay["replay_id"] }.first(SyncService::MAX_REPLAYS)
    end

    def shares_of(field)
      counts = Hash.new(0)
      days.each { |day| day.public_send(field).each { |key, count| counts[key] += count.to_i } }
      total = counts.values.sum
      return [] if total.zero?

      counts.sort_by { |key, count| [-count, key] }.map { |key, count| [key, count, count.fdiv(total)] }
    end
  end
end
