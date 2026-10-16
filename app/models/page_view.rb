# encoding: UTF-8

require "csv"

class PageView
  include Mongoid::Document
  include ReadOnly
  include DatedByDay

  CSV_HEADERS = ["URL", "Views", "Unique visitors", "Bot views", "Countries", "Created", "Last updated"].freeze
  # Visitors and bots aren't counted by day, so a span has neither.
  PERIOD_CSV_HEADERS = ["URL", "Views", "Countries", "Created", "Last updated"].freeze
  # Below this many hits, a page's bot share is mostly noise.
  MIN_HITS_FOR_BOT_SHARE = 20

  field :slug, type: String
  field :url, type: String
  # Undated, so they're kept apart from countriesByDay and added to it.
  field :countries, type: Hash, default: {}, as: :legacy_countries
  # Undated, so they're kept apart from devicesByDay and referrersByDay.
  field :devices, type: Hash, default: {}, as: :legacy_devices
  field :referrers, type: Hash, default: {}, as: :legacy_referrers
  # camelCase because these are the frontend's own keys in the shared live database.
  field :viewsByDay, type: Hash, default: {}, as: :legacy_views_by_day
  field :countriesByDay, type: Hash, default: {}, as: :countries_by_day
  field :devicesByDay, type: Hash, default: {}, as: :devices_by_day
  field :referrersByDay, type: Hash, default: {}, as: :referrers_by_day
  field :uniqueVisitorCount, type: Integer, default: 0, as: :unique_visitor_count
  field :visitorCount, type: Integer, default: 0, as: :visitor_count
  field :botCount, type: Integer, default: 0, as: :bot_count
  field :createdAt, type: Time, as: :created_at
  field :updatedAt, type: Time, as: :updated_at

  def countries
    all_time(legacy_countries, countries_by_day)
  end

  def devices
    all_time(legacy_devices, devices_by_day)
  end

  def referrers
    all_time(legacy_referrers, referrers_by_day)
  end

  def views_within(period)
    from, to = period.from.iso8601, period.to.iso8601
    views_by_day.sum { |day, count| day.between?(from, to) ? count : 0 }
  end

  # Days from before countries were dated count as Unknown, so the countries add up
  # to the span's views.
  def countries_within(period)
    within(legacy_views_by_day.transform_values { |count| {BlogStats::UNKNOWN_COUNTRY => count} }, period)
      .merge(within(countries_by_day, period)) { |_, legacy, dated| legacy + dated }
  end

  def devices_within(period)
    within(devices_by_day, period)
  end

  def referrers_within(period)
    within(referrers_by_day, period)
  end

  # The deploy day can appear in both the legacy totals and the dated
  # breakdown, holding the counts from either side of the switch, so the two
  # are added rather than one replacing the other.
  def views_by_day
    countries_by_day.each_with_object(legacy_views_by_day.transform_values(&:to_i)) do |(day, counts), totals|
      totals[day] = totals.fetch(day, 0) + counts.sum { |_, count| count.to_i }
    end
  end

  class << self
    # Bots have no dates, so only the all-time counts say how many there were.
    # Summed in the database, since every page would otherwise be loaded just
    # to add up two numbers.
    def hit_totals
      row = collection.aggregate([{"$group" => {"_id" => nil, "bots" => {"$sum" => "$botCount"}, "humans" => {"$sum" => "$visitorCount"}}}]).first || {}
      {bots: row["bots"].to_i, humans: row["humans"].to_i}
    end

    # All time, as bots aren't dated. Highest share first, since a page bots
    # favour is the one whose view count most needs the bots kept out.
    def bot_shares(limit: 15)
      only(:slug, :botCount, :visitorCount).filter_map do |page_view|
        hits = page_view.bot_count + page_view.visitor_count
        [page_view.slug, page_view.bot_count, page_view.visitor_count, page_view.bot_count.fdiv(hits)] if hits >= MIN_HITS_FOR_BOT_SHARE
      end.sort_by { |slug, bots, _, share| [-share, -bots, slug] }.first(limit)
    end

    def to_csv(page_views = order(visitor_count: :desc), period: nil)
      CSV.generate do |csv|
        csv << (period ? PERIOD_CSV_HEADERS : CSV_HEADERS)
        page_views.each do |page_view|
          countries = period ? page_view.countries_within(period) : page_view.countries
          csv << [
            page_view.url, *(period ? [page_view.views_within(period)] : [page_view.visitor_count, page_view.unique_visitor_count, page_view.bot_count]),
            countries.sort_by { |_, count| -count }.map { |code, count| "#{code}: #{count}" }.join("; ").presence,
            page_view.created_at&.utc&.iso8601(3), page_view.updated_at&.utc&.iso8601(3)
          ]
        end
      end
    end
  end

  private

  def all_time(legacy, by_day)
    by_day.each_value.with_object(legacy.transform_values(&:to_i)) do |day, totals|
      day.each { |key, count| totals[key] = totals.fetch(key, 0) + count.to_i }
    end
  end

  # ISO days sort as dates, so the period is compared as strings.
  def within(by_day, period)
    from, to = period.from.iso8601, period.to.iso8601
    by_day.each_with_object(Hash.new(0)) do |(day, counts), totals|
      counts.each { |key, count| totals[key] += count.to_i } if day.between?(from, to)
    end
  end

  # A day the frontend wrote oddly is left out rather than breaking the page.
  def parse_day(day)
    Date.iso8601(day.to_s)
  rescue Date::Error
    nil
  end
end
