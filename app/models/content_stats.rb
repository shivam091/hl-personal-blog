# encoding: UTF-8

class ContentStats
  # Long enough that a post still drawing readers is worth updating.
  STALE_AFTER = 6.months
  MIN_VIEWS_TO_REFRESH = 20
  CSV_HEADERS = [
    "URL", "Title", "Type", "Published", "Updated", "Views", "Likes", "Search clicks",
    "Search impressions", "In sitemap", "Indexed", "Tags"
  ].freeze
  EXPORTS = {
    "entries" => "Content",
    "not-in-search" => "Not shown in search",
    "search-readers" => "Search readers who don't stay",
    "reading" => "How far readers get"
  }.freeze
  # Published this recently, an entry may simply not have been shown yet,
  # so it's marked rather than counted as stuck.
  NEW_ENTRY_DAYS = 14
  # Below this, an entry's engagement rate is mostly noise.
  MIN_SEARCH_CLICKS = 10
  ORGANIC_CHANNEL = "Organic Search"

  Item = Struct.new(:entry, :path, :views, :likes, :clicks, :impressions, :crawled, :indexed, keyword_init: true) do
    def type
      entry.type
    end

    def search_gap
      if !crawled then "Not in the sitemap"
      elsif !indexed then "Not indexed"
      else "Indexed, not shown"
      end
    end
  end

  SearchReaders = Struct.new(:item, :sessions, :engagement_rate, :engagement_seconds_per_session, :below_site, keyword_init: true)

  Reading = Struct.new(:item, :views, :engagement_seconds_per_reader, :read_through, keyword_init: true)

  attr_reader :blog_stats

  def initialize(blog_stats, search: nil, coverage: IndexCoverage.new, within: nil)
    @blog_stats = blog_stats
    @search = search
    @coverage = coverage
    @within = within
  end

  # Nil unless a comparison is picked and the days compared with have any
  # reading, since every entry would otherwise read as new.
  def previous
    return @previous if defined?(@previous)

    earlier = self.class.new(blog_stats, search: @search, coverage: @coverage, within: period.previous) if period.compare? && !@within
    @previous = (earlier if earlier&.items&.any? { |item| item.views.positive? || item.likes.positive? || item.clicks.positive? })
  end

  # Search Console's figures are only compared once the period before was
  # synced, as every entry would otherwise read as having gained its clicks.
  def previous_search?
    !previous.nil? && search_compared?
  end

  def previous_item(item)
    previous&.items_by_path&.[](item.path)
  end

  def items_by_path
    @items_by_path ||= items.index_by(&:path)
  end

  def items
    @items ||= begin
      views = blog_stats.by_page(:views, period)
      likes = blog_stats.by_page(:likes, period)
      search_pages = (@search.pages(period) if @search && (!@within || search_compared?)) || {}
      FeedEntry.includes(:tags, :categories).order(published_at: :desc).map do |entry|
        path = IndexCoverage.path_of(entry.url)
        search = search_pages[path]
        Item.new(
          entry: entry,
          path: path,
          views: views.fetch(path, 0),
          likes: likes.fetch(path, 0),
          clicks: search&.clicks.to_i,
          impressions: search&.impressions.to_i,
          crawled: @coverage.crawled_paths.include?(path),
          indexed: @coverage.indexed_paths.include?(path)
        )
      end
    end
  end

  def any?
    items.any?
  end

  # Averages per entry, so a type with many entries doesn't win on volume alone.
  def by_type
    FeedEntry::TYPES.map do |type|
      of_type = items.select { |item| item.type == type }
      published = of_type.count do |item|
        item.entry.published_at.to_date.between?(period.from, period.to)
      end
      views = of_type.sum(&:views)

      {
        type: type,
        entries: of_type.size,
        published: published,
        views: views,
        likes: of_type.sum(&:likes),
        clicks: of_type.sum(&:clicks),
        average_views: (views.fdiv(of_type.size) if of_type.any?)
      }
    end
  end

  # Each type's views over the period compared with, by the same pages as now,
  # so a type isn't judged against entries it didn't have yet.
  def previous_views_by_type
    before = blog_stats.by_page(:views, period.previous)
    FeedEntry::TYPES.to_h { |type| [type, items.select { |item| item.type == type }.sum { |item| before.fetch(item.path, 0) }] }
  end

  def funnel
    [
      ["Published", items.size],
      ["In the sitemap", items.count(&:crawled)],
      ["Indexed", items.count(&:indexed)],
      ["Shown in search", items.count { |item| item.impressions.positive? }],
      ["Clicked from search", items.count { |item| item.clicks.positive? }],
      ["Read", items.count { |item| item.views.positive? }],
      ["Liked", items.count { |item| item.likes.positive? }]
    ]
  end

  def refresh_candidates(limit: 10, today: Date.current)
    items.select { |item| worth_refreshing?(item, today: today) }
      .sort_by { |item| [-item.views, item.path] }.first(limit)
  end

  def worth_refreshing?(item, today: Date.current)
    item.entry.last_modified_at.to_date < today - STALE_AFTER && item.views >= MIN_VIEWS_TO_REFRESH
  end

  def tags(limit: 15)
    taxonomy(:tag, limit) { |item| item.entry.tags.map(&:name) }
  end

  def categories(limit: 15)
    taxonomy(:category, limit) { |item| item.entry.categories.map(&:name) }
  end

  DecayPoint = Struct.new(:item, :age_months, keyword_init: true)
  # Six by default, so the weeks where a fade shows aren't squeezed into a
  # corner by entries long out.
  DECAY_SPANS = [3, 6, 12].freeze
  DECAY_MONTHS = 6

  # Entries published after the period are left out, as they couldn't have
  # been read in it.
  def decay_points(months: DECAY_MONTHS)
    items.filter_map do |item|
      published = item.entry.published_at.to_date
      next if published > period.to

      age = ((period.to - published).to_i / 30.44).round(1)
      DecayPoint.new(item: item, age_months: age) if age <= months
    end
  end

  def cadence(today: Date.current)
    months = (0..11).map { |back| (today << back).beginning_of_month }.reverse
    counts = items.group_by do |item|
      [item.entry.published_at.to_date.beginning_of_month, item.type]
    end.transform_values(&:size)

    months.map do |month|
      [
        month,
        FeedEntry::TYPES.to_h { |type| [type, counts.fetch([month, type], 0)] }
      ]
    end
  end

  CalendarDay = Struct.new(:date, :entries, keyword_init: true)

  # Starts on the 1st of a month so each month has a week its label can sit
  # on; days before that stay blank rather than form a month with no label. An
  # unknown type shows every entry rather than none, so a mistyped or old link
  # still shows a calendar.
  def calendar(type: nil, today: Date.current)
    type = type.presence_in(FeedEntry::TYPES)
    first = today.beginning_of_month - 11.months
    shown = type ? items.select { |item| item.entry.type == type } : items
    by_day = shown.group_by { |item| item.entry.published_at.to_date }
    (first.beginning_of_week..today).each_slice(7).map do |week|
      week.map do |date|
        CalendarDay.new(date: date, entries: by_day.fetch(date, []).map(&:entry)) unless date < first
      end
    end
  end

  Gap = Struct.new(:from, :to, :days, keyword_init: true)
  Streak = Struct.new(:from, :to, :weeks, keyword_init: true)
  Rhythm = Struct.new(:last_published, :since_last, :median_gap, :longest_gap, :longest_streak, :current_streak, keyword_init: true)

  # Between publishing days rather than entries, so two entries out on one
  # day don't read as a gap of none.
  def gaps(type: nil)
    publishing_days(type).each_cons(2).map { |from, to| Gap.new(from: from, to: to, days: (to - from).to_i) }
  end

  # Over all time rather than the period, since a gap or streak can reach
  # back further than any period would. Streaks are in weeks, as a blog
  # isn't written daily.
  def rhythm(type: nil, today: Date.current)
    days = publishing_days(type)
    return if days.empty?

    waits = gaps(type: type)
    lengths = waits.map(&:days).sort
    weeks = days.map(&:beginning_of_week).uniq
    streaks = weeks.slice_when { |a, b| b != a + 7 }.map do |run|
      Streak.new(from: run.first, to: run.last, weeks: run.size)
    end
    latest = streaks.last
    Rhythm.new(
      last_published: days.last,
      since_last: (today - days.last).to_i,
      median_gap: median(lengths),
      longest_gap: waits.max_by { |gap| [gap.days, gap.to] },
      longest_streak: streaks.max_by { |streak| [streak.weeks, streak.to] },
      # This week may simply not have its entry yet, so a run ending last
      # week still counts as going.
      current_streak: latest.to >= today.beginning_of_week - 7 ? latest.weeks : 0
    )
  end

  # Spans a writer thinks in, so a typo fixed the week an entry went out
  # isn't lumped in with a rewrite a year on. A same-day edit counts as
  # none, since the feed stamps an entry as it's first put up.
  UPDATE_BANDS = {
    "Never" => 0..0,
    "Within a week" => 1..7,
    "Within a month" => 8..30,
    "Within 6 months" => 31..182,
    "Later" => 183..
  }.freeze

  Updates = Struct.new(:bands, :updated, :median_days, :latest, keyword_init: true)

  # By the latest update only, as the feed keeps no earlier ones. Over every
  # entry, since when an entry was updated doesn't depend on the period.
  def updates(limit: 8)
    waits = items.to_h { |item| [item, [(item.entry.last_modified_at.to_date - item.entry.published_at.to_date).to_i, 0].max] }
    updated = waits.select { |_, days| days.positive? }
    Updates.new(
      bands: UPDATE_BANDS.transform_values { |range| waits.values.count { |days| range.cover?(days) } },
      updated: updated.size,
      median_days: median(updated.values.sort),
      latest: updated.keys.sort_by { |item| [-item.entry.last_modified_at.to_i, item.path] }.first(limit)
    )
  end

  # Until Search Console has been synced every entry would read as unseen.
  def search_synced?
    @search.present? && @search.any?
  end

  # Oldest first, since the longer an entry has gone unseen the less likely
  # Google is to start showing it on its own. Entries published after the
  # period are left out, as they couldn't have been shown in it.
  def not_in_search(limit: 10)
    return [] unless search_synced?

    rows = items.select { |item| item.impressions.zero? && item.entry.published_at.to_date <= period.to }
    rows.sort_by { |item| [item.entry.published_at, item.path] }.first(limit || rows.size)
  end

  # Told from entries never shown, since a drop needs a different fix than
  # one that never started; only once the period before was synced.
  def dropped_from_search?(item)
    previous_search? && previous_item(item)&.impressions.to_i.positive? && item.impressions.zero?
  end

  def new_entry?(item)
    item.entry.published_at.to_date > period.to - NEW_ENTRY_DAYS
  end

  # Every entry with search clicks or search sessions, so one GA saw no
  # search readers for still shows beside its clicks.
  def search_readers
    return [] if other_country?

    @search_readers ||= begin
      site_rate = organic_totals.engagement_rate
      items.filter_map do |item|
        row = organic_pages[item.path]
        next if item.clicks.zero? && row.nil?

        SearchReaders.new(
          item: item,
          sessions: row&.sessions.to_i,
          engagement_rate: (row.engagement_rate if row&.sessions&.positive?),
          engagement_seconds_per_session: (row.average_engagement_seconds_per_session if row&.sessions&.positive?),
          below_site: row.present? && row.sessions.positive? && row.engagement_rate < site_rate
        )
      end
    end
  end

  # Clicked often from search yet left sooner than the site's other search
  # readers leave: the entry ranks, but doesn't give searchers what they
  # came for, so its opening is the part to rework.
  def search_leaks(limit: 10)
    rows = search_readers.select { |row| row.below_site && row.item.clicks >= MIN_SEARCH_CLICKS }
    rows.sort_by { |row| [-row.item.clicks, row.item.path] }.first(limit || rows.size)
  end

  def site_search_engagement_rate
    organic_totals.engagement_rate if organic_totals.sessions.positive?
  end

  def most_viewed(limit: 25)
    ranked = items.sort_by { |item| [-item.views, item.path] }
    ranked.first(limit || ranked.size)
  end

  # Most read first, since that's where a reader not finishing costs most.
  def reading(limit: 15)
    return [] if other_country?

    @reading ||= begin
      pages = analytics_pages
      scrolls = scroll_counts
      items.filter_map do |item|
        row = pages[item.path]
        next unless row && row.views >= Google::Analytics::Insights::MIN_VIEWS

        Reading.new(
          item: item,
          views: row.views,
          engagement_seconds_per_reader: row.average_engagement_seconds,
          read_through: scrolls.fetch(item.path, 0).fdiv(row.views)
        )
      end.sort_by { |row| [-row.views, row.item.path] }
    end
    @reading.first(limit || @reading.size)
  end

  def site_engagement_seconds_per_reader
    analytics_totals.average_engagement_seconds if analytics_totals.active_users.positive?
  end

  def site_read_through
    analytics_totals.views.positive? ? scroll_counts.values.sum.fdiv(analytics_totals.views) : nil
  end

  def scrolls?
    scroll_counts.values.any?(&:positive?)
  end

  def to_csv(export = "entries")
    searched = previous_search?
    counted = ->(item, field, value = item.public_send(field)) do
      before = previous_item(item)
      CompareChange.cell(value, (before.public_send(field) if before), compare: !previous.nil? && (searched || !%i[clicks impressions].include?(field)))
    end
    CSV.generate do |csv|
      case export
      when "not-in-search"
        csv << [
          "URL", "Title", "Type", "Published", "In sitemap", "Indexed", "Why",
          "Published in the last #{NEW_ENTRY_DAYS} days", *("Impressions before" if previous_search?)
        ]
        not_in_search(limit: nil).each do |item|
          entry = item.entry
          csv << [
            entry.url,
            entry.name,
            entry.type,
            entry.published_at&.utc&.iso8601,
            yes_no(item.crawled),
            yes_no(item.indexed),
            item.search_gap,
            yes_no(new_entry?(item)),
            *(previous_item(item)&.impressions.to_i if previous_search?)
          ]
        end
      when "search-readers"
        csv << [
          "URL", "Title", "Search clicks", "Search impressions", "Search sessions (GA)", "Engagement rate",
          "Engagement per session (s)", "Under the site's rate"
        ]
        search_readers.sort_by { |row| [-row.item.clicks, row.item.path] }.each do |row|
          csv << [
            row.item.entry.url,
            row.item.entry.name,
            counted.(row.item, :clicks),
            counted.(row.item, :impressions),
            row.sessions,
            row.engagement_rate&.round(4),
            row.engagement_seconds_per_session&.round(1),
            yes_no(row.below_site)
          ]
        end
      when "reading"
        csv << ["URL", "Title", "Views (GA)", "Engagement per reader (s)", "Read-through rate"]
        earlier = previous&.reading(limit: nil)&.index_by { |row| row.item.path }.presence
        reading(limit: nil).each do |row|
          before = earlier&.[](row.item.path)
          csv << [
            row.item.entry.url,
            row.item.entry.name,
            CompareChange.cell(row.views, before&.views, compare: !earlier.nil?),
            CompareChange.cell(row.engagement_seconds_per_reader.round(1), before&.engagement_seconds_per_reader&.round(1), compare: !earlier.nil?),
            CompareChange.cell(row.read_through.round(4), before&.read_through&.round(4), compare: !earlier.nil?)
          ]
        end
      else
        csv << CSV_HEADERS
        items.each do |item|
          entry = item.entry
          csv << [
            entry.url,
            entry.name,
            entry.type,
            entry.published_at&.utc&.iso8601,
            entry.last_modified_at&.utc&.iso8601,
            counted.(item, :views),
            counted.(item, :likes),
            counted.(item, :clicks),
            counted.(item, :impressions),
            yes_no(item.crawled),
            yes_no(item.indexed),
            entry.tag_names.join(", ")
          ]
        end
      end
    end
  end

  private

  def period
    @within || blog_stats.period
  end

  # Search Console and Analytics aren't split by country, so a picked
  # country's dates would only read back this period's own figures.
  def other_country?
    !@within.nil? && blog_stats.period.compare_countries?
  end

  def search_compared?
    @search.present? && @search.compared? && !other_country?
  end

  def yes_no(value)
    value ? "Yes" : "No"
  end

  # Halfway between the middle two of an even count, so two waits of 8 and
  # 152 days don't read as a typical wait of 152.
  def median(sorted)
    ((sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0).round if sorted.any?
  end

  # An unknown type counts every entry rather than none, so a mistyped or old
  # link still shows the gaps and streaks.
  def publishing_days(type = nil)
    type = type.presence_in(FeedEntry::TYPES)
    @publishing_days ||= {}
    @publishing_days[type] ||= items.filter_map do |item|
      item.entry.published_at.to_date if type.nil? || item.entry.type == type
    end.uniq.sort
  end

  # An entry counts towards each of its names, so a row's totals can add up
  # to more than the site's.
  def taxonomy(key, limit)
    items.flat_map { |item| yield(item).map { |name| [name, item] } }.group_by(&:first).map do |name, pairs|
      named = pairs.map(&:last)
      views = named.sum(&:views)
      likes = named.sum(&:likes)
      {
        key => name,
        entries: named.size,
        views: views,
        likes: likes,
        clicks: named.sum(&:clicks),
        average_views: views.fdiv(named.size),
        like_rate: (likes.fdiv(views) if views >= BlogStats::MIN_VIEWS_FOR_RATE)
      }
    end.sort_by { |row| [-row[:views], row[key]] }.then { |rows| rows.first(limit || rows.size) }
  end

  def organic_criteria
    period.apply(Google::Analytics::SourceStat.where(channel_group: ORGANIC_CHANNEL))
  end

  def organic_pages
    @organic_pages ||= Google::Analytics::SourceStat.grouped(organic_criteria, by: [:page_path]).index_by { |row| row[:page_path] }
  end

  def organic_totals
    @organic_totals ||= Google::Analytics::SourceStat.grouped(organic_criteria, by: []).totals
  end

  # GA's own views rather than the blog's, so read-through divides scrolls
  # by views counted the same way.
  def analytics_pages
    @analytics_pages ||= Google::Analytics::Stat.grouped(period.apply(Google::Analytics::Stat.all), by: [:page_path]).index_by { |row| row[:page_path] }
  end

  def analytics_totals
    @analytics_totals ||= Google::Analytics::Stat.grouped(period.apply(Google::Analytics::Stat.all), by: []).totals
  end

  def scroll_counts
    @scroll_counts ||= Google::Analytics::EventStat.grouped(period.apply(Google::Analytics::EventStat.where(event_name: Google::Analytics::Insights::SCROLL_EVENT)), by: [:page_path])
      .to_h { |row| [row[:page_path], row.event_count] }
  end
end
