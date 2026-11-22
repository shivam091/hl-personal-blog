# encoding: UTF-8

# Loaded once for a period and country, so every figure is cut the same way
# without each one re-reading the frontend's collections.
class BlogStats
  METRICS = %i[views likes subscribers messages].freeze
  # The frontend writes "UNKNOWN" when the edge sends no country, and older
  # records have none at all; one code keeps them in a single row.
  UNKNOWN_COUNTRY = "ZZ"
  # Below these, a rate or a growth figure is mostly noise (1 → 4 views reads
  # as +300%).
  MIN_VIEWS_FOR_RATE = 100
  MIN_VIEWS_FOR_GROWTH = 20

  Fact = Struct.new(:date, :country, :slug, :count)

  attr_reader :period, :country, :undated_likes, :country_tracking_since, :breakdowns_tracked_since

  def initialize(period, country: nil)
    @period = period
    @country = country
    # Covers the period compared with too, so comparing needs no second
    # load; picked dates can fall after this period as well as before it.
    previous = period.previous
    @span = [previous.from, period.from].min..[previous.to, period.to].max
    @undated_likes = 0
    @dated_breakdowns = {devices: Hash.new { |hash, date| hash[date] = Hash.new(0) },
                         referrers: Hash.new { |hash, date| hash[date] = Hash.new(0) }}
    @facts = load_facts
  end

  # Not split by country by the frontend, so these always cover every
  # country; the views from before they were dated are only in the pages'
  # all-time totals.
  def devices(within = period)
    dated_breakdown(:devices, within)
  end

  def referrers(within = period)
    dated_breakdown(:referrers, within)
  end

  # Counted across the whole period, so a reader who came back on several
  # days counts once, unlike adding up each day's visitors.
  def unique_visitors(within = period, slug: nil)
    stages = [{"$match" => visitor_markers(within, slug).selector}, {"$group" => {"_id" => "$ipHash"}}, {"$count" => "visitors"}]
    PageViewSeen.collection.aggregate(stages).first&.fetch("visitors") || 0
  end

  def daily_unique_visitors(within = period)
    stages = [{"$match" => visitor_markers(within).selector}, {"$group" => {"_id" => {"day" => "$day", "ip" => "$ipHash"}}}, {"$group" => {"_id" => "$_id.day", "visitors" => {"$sum" => 1}}}]
    counts = PageViewSeen.collection.aggregate(stages).to_h { |row| [row["_id"], row["visitors"]] }
    (within.from..within.to).map { |date| counts.fetch(date.iso8601, 0) }
  end

  # The frontend only began keeping markers, and recording countries on them,
  # from some day, so a period reaching back further would undercount.
  def visitors_counted_since
    return @visitors_counted_since if defined?(@visitors_counted_since)

    markers = country ? PageViewSeen.where(:country.ne => nil) : PageViewSeen.all
    @visitors_counted_since = parse_day(markers.order(day: :asc).only(:day).first&.day)
  end

  def likes_counted_since
    return @likes_counted_since if defined?(@likes_counted_since)

    @likes_counted_since = PageLike.first_day
  end

  def visitors_complete?(within = period)
    visitors_counted_since.present? && within.from >= visitors_counted_since
  end

  def total(metric, within = period, country: within.country || self.country)
    facts(metric, within, country).sum(&:count)
  end

  # Zero-filled, so a quiet day draws as a dip rather than being skipped.
  def daily(metric, within = period, country: within.country || self.country)
    counts = Hash.new(0)
    facts(metric, within, country).each { |fact| counts[fact.date] += fact.count }
    (within.from..within.to).map { |date| counts[date] }
  end

  # Zero-filled daily series for every country or page in one pass, so a row
  # per key doesn't re-scan every fact.
  def daily_by(metric, key, within = period, country: within.country || self.country)
    offsets = (within.from..within.to).each_with_index.to_h
    series = {}
    facts(metric, within, country).each do |fact|
      (series[fact.public_send(key)] ||= Array.new(offsets.size, 0))[offsets[fact.date]] += fact.count
    end
    series.tap { series.default_proc = proc { Array.new(offsets.size, 0) } }
  end

  # Weeks start on Monday, so a period cut mid-week still lines up with the
  # calendar.
  def weekly(metric, within = period, country: within.country || self.country)
    counts = Hash.new(0)
    facts(metric, within, country).each { |fact| counts[fact.date.beginning_of_week] += fact.count }
    (within.from.beginning_of_week..within.to).step(7).to_h { |week| [week, counts[week]] }
  end

  def by_country(metric, within = period)
    sum_by(facts(metric, within, nil), &:country)
  end

  # Against the compared country's total over the same dates when one is
  # picked, so every country reads against one audience rather than itself.
  def compared_by_country(metric)
    previous = period.previous
    period.compare_countries? ? Hash.new(total(metric, previous)) : by_country(metric, previous)
  end

  def by_page(metric, within = period, country: within.country || self.country)
    sum_by(facts(metric, within, country), &:slug)
  end

  def by_page_and_country(metric, within = period)
    facts(metric, within, nil).each_with_object(Hash.new { |hash, slug| hash[slug] = Hash.new(0) }) do |fact, cells|
      cells[fact.slug][fact.country] += fact.count
    end
  end

  def fastest_growing_countries(limit: 5)
    current = by_country(:views)
    previous = by_country(:views, period.previous)
    current.filter_map do |code, count|
      next if code == UNKNOWN_COUNTRY || count < MIN_VIEWS_FOR_GROWTH

      before = previous.fetch(code, 0)
      [code, count, before, before.zero? ? nil : (count - before).to_f / before]
    end.sort_by { |code, count, _, growth| [growth ? -growth : -Float::INFINITY, -count, code] }.first(limit)
  end

  # Ranked by the change in views rather than its percentage, so a page that
  # went from 2 to 8 doesn't outrank one that gained hundreds.
  def page_changes(limit: 5)
    current = by_page(:views)
    previous = by_page(:views, period.previous)
    rows = (current.keys | previous.keys).filter_map do |slug|
      now = current.fetch(slug, 0)
      before = previous.fetch(slug, 0)
      [slug, now, before, now - before] if [now, before].max >= MIN_VIEWS_FOR_GROWTH && now != before
    end
    rising, falling = rows.partition { |row| row.last.positive? }
    [rising.sort_by { |row| [-row.last, row.first] }.first(limit), falling.sort_by { |row| [row.last, row.first] }.first(limit)]
  end

  # Starts from everyone who subscribed before the period, so the line shows
  # the list's real size rather than growth from zero.
  def subscriber_totals(within = period)
    shown = within.country || country
    running = NewsletterSubscriber.where(:subscribed_at.lt => within.from.in_time_zone.beginning_of_day).pluck(:country)
      .count { |code| shown.nil? || country_code(code) == shown }
    daily(:subscribers, within).map { |count| running += count }
  end

  # Weeks for a short period and months for a long one, so there are enough
  # buckets without each one being too thin. The top countries are the
  # period's, so a country keeps its place from one bucket to the next.
  def country_shares(limit: 5)
    shares(ranked_countries.first(limit), facts(:views, period, nil).map { |fact| [fact.date, fact.country, fact.count] })
  end

  # Cut the same way as country shares, so a drift towards phones or away
  # from a referrer reads like a drift between countries. Every country,
  # since the frontend doesn't split these by one.
  def breakdown_shares(kind, limit: 5)
    top = dated_breakdown(kind, period).reject { |_, count| count.zero? }.sort_by { |key, count| [-count, key] }.first(limit).map(&:first)
    counts = @dated_breakdowns[kind].flat_map do |date, keys|
      date.between?(period.from, period.to) ? keys.map { |key, count| [date, key, count] } : []
    end
    shares(top, counts)
  end

  # Per country, so one that visits a lot but never subscribes stands out
  # from one that converts.
  def funnel(extra = {})
    views, likes, subscribers, messages = METRICS.map { |metric| by_country(metric) }
    trends = daily_by(:views, :country, country: nil)
    codes = (views.keys | likes.keys | subscribers.keys | messages.keys)
    codes.map do |code|
      FunnelRow.new(
        country: code,
        views: views.fetch(code, 0),
        likes: likes.fetch(code, 0),
        subscribers: subscribers.fetch(code, 0),
        messages: messages.fetch(code, 0),
        trend: trends[code], **extra.transform_values { |counts| counts[code] }
      )
    end
  end

  FUNNEL_CSV_HEADERS = [
    "Country", "Views", "Likes", "Like rate", "Subscribers", "Subscribers per view", "Messages",
    "Search clicks", "GA views", "Banners", "Accept rate"].freeze

  FunnelRow = Struct.new(
    :country, :views, :likes, :subscribers, :messages, :trend, :search_clicks,
    :analytics_views, keyword_init: true
  ) do
    class << self
      def to_csv(rows, ai: nil, previous: nil, banners: nil)
        ai = nil unless ai&.covered
        counted = ->(row, metric) { CompareChange.cell(row.public_send(metric), previous&.dig(metric, row.country), compare: !previous.nil?) }
        extra = ->(row, metric) { row.public_send(metric).nil? ? nil : CompareChange.cell(row.public_send(metric), previous&.dig(metric, row.country).to_i, compare: previous&.key?(metric)) }
        CSV.generate do |csv|
          csv << [*FUNNEL_CSV_HEADERS, *("AI impressions #{ai.covered.begin.iso8601} to #{ai.covered.end.iso8601}" if ai)]
          rows.each do |row|
            csv << [
              row.country,
              counted.(row, :views),
              counted.(row, :likes),
              row.like_rate&.round(4),
              counted.(row, :subscribers),
              row.subscriber_rate&.round(4),
              counted.(row, :messages),
              extra.(row, :search_clicks),
              extra.(row, :analytics_views),
              banners&.shown(row.country),
              banners&.acceptance_rate(row.country)&.round(4),
              *(ai.countries.fetch(row.country, 0) if ai)
            ]
          end
        end
      end
    end

    def like_rate
      rate(likes)
    end

    def subscriber_rate
      rate(subscribers)
    end

    private

    def rate(count)
      count.to_f / views if views >= MIN_VIEWS_FOR_RATE
    end
  end

  # Every country with any record, so the filter can't offer one that
  # matches nothing.
  def countries
    @facts.values.flatten.map(&:country).uniq.sort
  end

  # The views before country tracking began count as Unknown, so filtering by
  # a country undercounts any period that starts before then.
  def country_gap?
    country.present? && country_tracking_since.present? && period.from < country_tracking_since
  end

  private

  def facts(metric, within, country)
    @facts.fetch(metric).select do |fact|
      fact.date.between?(within.from, within.to) && (country.nil? || fact.country == country)
    end
  end

  def collect_breakdowns(kind, by_day)
    tracked = by_day.keys.filter_map { |day| parse_day(day) }.min
    @breakdowns_tracked_since = [@breakdowns_tracked_since, tracked].compact.min
    by_day.each do |day, counts|
      next unless (date = dated(day))

      counts.each { |key, count| @dated_breakdowns[kind][date][key] += count.to_i }
    end
  end

  def dated_breakdown(kind, within)
    @dated_breakdowns[kind].each_with_object(Hash.new(0)) do |(date, counts), totals|
      counts.each { |key, count| totals[key] += count } if date.between?(within.from, within.to)
    end
  end

  # Markers from before the frontend recorded countries have none, and count
  # as Unknown like any other record without one.
  def visitor_markers(within, slug = nil)
    markers = PageViewSeen.where(:day.gte => within.from.iso8601, :day.lte => within.to.iso8601)
    markers = markers.where(slug: slug) if slug
    code = within.country || country
    return markers unless code

    code == UNKNOWN_COUNTRY ? markers.where(:country.not => /\A[A-Za-z]{2}\z/) : markers.where(country: code)
  end

  # Unknown is left to Other, since it isn't a place an audience can move to.
  def ranked_countries
    by_country(:views).reject { |code, _| code == UNKNOWN_COUNTRY }.sort_by { |code, count| [-count, code] }.map(&:first)
  end

  def shares(top, counts)
    weekly = period.days <= 120
    buckets = Hash.new { |hash, start| hash[start] = Hash.new(0) }
    counts.each do |date, key, count|
      start = weekly ? date.beginning_of_week : date.beginning_of_month
      buckets[start][top.include?(key) ? key : :other] += count
    end
    {keys: top, unit: weekly ? :week : :month, buckets: buckets.sort.to_h}
  end

  def sum_by(facts)
    facts.each_with_object(Hash.new(0)) { |fact, totals| totals[yield(fact)] += fact.count }
  end

  def load_facts
    {views: view_facts, likes: like_facts, subscribers: subscriber_facts, messages: message_facts}
  end

  # Days before countriesByDay existed only have a total, so they become
  # Unknown-country views and the per-country figures still add up to it.
  def view_facts
    PageView.only(:slug, :viewsByDay, :countriesByDay, :devicesByDay, :referrersByDay).flat_map do |page_view|
      tracked = page_view.countries_by_day.keys.filter_map { |day| parse_day(day) }.min
      @country_tracking_since = [@country_tracking_since, tracked].compact.min
      collect_breakdowns(:devices, page_view.devices_by_day)
      collect_breakdowns(:referrers, page_view.referrers_by_day)
      legacy = page_view.legacy_views_by_day.filter_map do |day, count|
        (date = dated(day)) && Fact.new(date, UNKNOWN_COUNTRY, page_view.slug, count.to_i)
      end
      legacy + country_facts(page_view.slug, page_view.countries_by_day)
    end
  end

  # Likes from before they were dated have no day to fall in, so they're
  # counted aside rather than letting the totals disagree with like_count.
  def like_facts
    PageLike.only(:slug, :likeCount, :countriesByDay).flat_map do |page_like|
      @undated_likes += [page_like.like_count - page_like.likes_by_day.values.sum, 0].max
      country_facts(page_like.slug, page_like.countries_by_day)
    end
  end

  def subscriber_facts
    record_facts(NewsletterSubscriber.where(subscribed_at: time_span).pluck(:subscribed_at, :country))
  end

  def message_facts
    record_facts(Message.where(created_at: time_span).pluck(:created_at, :country))
  end

  def country_facts(slug, countries_by_day)
    countries_by_day.flat_map do |day, counts|
      next [] unless (date = dated(day))

      counts.map { |code, count| Fact.new(date, country_code(code), slug, count.to_i) }
    end
  end

  def record_facts(rows)
    rows.map { |time, code| Fact.new(time.in_time_zone.to_date, country_code(code), nil, 1) }
  end

  # The frontend keys days by IST date, as the app's time zone is.
  def time_span
    @span.first.in_time_zone.beginning_of_day..@span.last.in_time_zone.end_of_day
  end

  def dated(day)
    (date = parse_day(day)) && @span.cover?(date) ? date : nil
  end

  # A day the frontend wrote oddly is left out rather than breaking every
  # figure.
  def parse_day(day)
    Date.iso8601(day.to_s)
  rescue Date::Error
    nil
  end

  def country_code(code)
    code.to_s.match?(/\A[A-Za-z]{2}\z/) ? code.upcase : UNKNOWN_COUNTRY
  end
end
