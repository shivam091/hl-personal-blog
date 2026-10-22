# encoding: UTF-8

# A month or a year of the blog on one page, every source together, so how
# it went can be read in one sitting and set against the one before.
class MonthAndYearReview
  FIRST_MONTH = Period::START
  TOP = 5

  # The year or month so far is set against the same days a year or month
  # earlier, since the stretch just before it is the end of the last one, not
  # like for like.
  Span = Struct.new(:key, :label, :from, :to, :compare, keyword_init: true) do
    # A comparison picked on the page replaces the span's own, which is only
    # the better default for a year not yet over.
    def period(picked = {})
      picked = picked.to_h.symbolize_keys.slice(:compare, :vs_from, :vs_to).compact_blank
      Period.new({from: from.iso8601, to: to.iso8601, compare: compare}.compact.merge(picked))
    end
  end
  Figure = Struct.new(:label, :icon, :hint, :current, :previous, :format, keyword_init: true)

  class << self
    # The month so far, then whole months that have ended since the blog began,
    # newest first, and the year so far then the years before, so the one in
    # progress can be read as it goes.
    def spans(today: Date.current)
      last_full_day = today - 1
      months = (1..).lazy.map { |back| (today << back).beginning_of_month }.take_while { |month| month >= FIRST_MONTH }.map do |month|
        Span.new(key: month.strftime("%Y-%m"), label: I18n.l(month, format: "%B %Y"), from: month, to: month.end_of_month)
      end.to_a
      this_year = Span.new(key: today.year.to_s, label: "#{today.year} so far", from: today.beginning_of_year, to: last_full_day, compare: "year")
      years = (FIRST_MONTH.year...today.year).to_a.reverse.map do |year|
        Span.new(key: year.to_s, label: year.to_s, from: Date.new(year), to: Date.new(year).end_of_year)
      end
      this_month = Span.new(key: today.strftime("%Y-%m"), label: "#{I18n.l(today, format: "%B %Y")} so far", from: today.beginning_of_month, to: last_full_day,
        compare: "month")
      months.unshift(this_month) if last_full_day >= this_month.from
      {months: months, years: [(this_year if last_full_day >= this_year.from), *years].compact}
    end

    # The month just ended by default, as that's the review most often read.
    def span(key, today: Date.current)
      months = spans(today: today)[:months]
      all = [*months, *spans(today: today)[:years]]
      all.find { |span| span.key == key.to_s } || months.find { |span| span.compare.nil? } || all.first
    end
  end

  attr_reader :stats, :search, :analytics, :ai

  def initialize(stats, search:, analytics:, ai: Google::SearchConsole::GenerativeAiSummary.new(stats.period))
    @stats = stats
    @search = search
    @analytics = analytics
    @ai = ai
  end

  def period
    stats.period
  end

  # Nil where a source hasn't synced the span before, so a first sync isn't
  # read as growth from nothing.
  def figures
    previous = period.previous
    search_before = search.previous_totals
    [
      Figure.new(label: "Views", icon: "eye", hint: "Human page views in the span; bots are counted apart and left out.",
        current: stats.total(:views), previous: stats.total(:views, previous)),
      Figure.new(label: "Likes", icon: "heart", hint: "Likes given in the span; each IP address can like a page once.",
        current: stats.total(:likes), previous: stats.total(:likes, previous)),
      Figure.new(label: "New subscribers", icon: "users", hint: "Newsletter sign-ups in the span.",
        current: stats.total(:subscribers), previous: stats.total(:subscribers, previous)),
      Figure.new(label: "Messages", icon: "message-square", hint: "Messages sent through the contact form in the span.",
        current: stats.total(:messages), previous: stats.total(:messages, previous)),
      Figure.new(label: "Entries published", icon: "rss", hint: "Posts, tutorials, snippets and series the feed dates to the span.",
        current: published.size, previous: published(previous).size),
      Figure.new(label: "Search clicks", icon: "mouse-pointer", hint: "Clicks from Google Search results to the blog, as Search Console counts them.",
        current: (search.totals.clicks if search.any?), previous: search_before&.clicks),
      Figure.new(label: "Search impressions", icon: "search", hint: "Times a blog page was shown in Google Search results.",
        current: (search.totals.impressions if search.any?), previous: search_before&.impressions),
      Figure.new(label: "AI impressions", icon: "sparkles",
        hint: "Times the blog appeared in an AI Overview or AI Mode answer, from uploads of Search Console's Generative AI report (#{ai.search_type || "none yet"}).",
        current: ai.total, previous: ai.previous_total),
      Figure.new(label: "Analytics sessions", icon: "activity", hint: "Visits Google Analytics recorded; readers who block it aren't counted.",
        current: (analytics.sessions.sessions if analytics.any?),
        previous: (analytics.sessions(previous).sessions if analytics.any? && analytics.previous?))
    ]
  end

  def to_csv
    CSV.generate do |csv|
      csv << (period.compare? ? ["Figure", "This span", "Span before", "Change"] : ["Figure", "This span"])
      figures.each do |figure|
        change = (figure.current - figure.previous).fdiv(figure.previous).round(4) if figure.current && figure.previous.to_f.positive?
        csv << (period.compare? ? [figure.label, figure.current, figure.previous, change] : [figure.label, figure.current])
      end
    end
  end

  def top_pages
    ranked(stats.by_page(:views)).first(TOP)
  end

  # Of the pages and countries listed, what each had in the span compared
  # with; nil with no comparison, so a list shows no change at all.
  def previous_views(kind)
    return unless period.compare?

    kind == :page ? stats.by_page(:views, period.previous) : stats.by_country(:views, period.previous)
  end

  def previous_queries
    search.previous_queries if period.compare?
  end

  # With the views each had in the span, so a new entry's start can be set
  # beside the older pages it's competing with.
  def new_entries
    views = stats.by_page(:views)
    published.map { |entry| [entry, views.fetch(IndexCoverage.path_of(entry.url), 0)] }
  end

  def top_countries
    ranked(stats.by_country(:views).except(BlogStats::UNKNOWN_COUNTRY)).first(TOP)
  end

  def top_queries
    search.any? ? search.top_queries(limit: TOP) : []
  end

  def movers
    period.compare? ? stats.page_changes(limit: TOP) : [[], []]
  end

  # Names for the pages listed, so a review reads as entries rather than
  # paths.
  def names
    @names ||= FeedEntry.only(:_id, :name).to_h { |entry| [IndexCoverage.path_of(entry.url), entry.name] }
  end

  private

  def published(within = period)
    FeedEntry.where(published_at: within.from.in_time_zone.beginning_of_day..within.to.in_time_zone.end_of_day)
      .order(published_at: :asc).only(:_id, :name, :type, :published_at).to_a
  end

  def ranked(counts)
    counts.reject { |_, count| count.zero? }.sort_by { |key, count| [-count, key.to_s] }
  end
end
