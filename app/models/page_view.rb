# encoding: UTF-8

require "csv"

class PageView
  include Mongoid::Document
  include ReadOnly
  include DatedByDay

  CSV_HEADERS = ["URL", "Views", "Unique visitors", "Bot views", "Countries", "Created", "Last updated"].freeze
  # Below this many hits, a page's bot share is mostly noise.
  MIN_HITS_FOR_BOT_SHARE = 20

  field :slug, type: String
  field :url, type: String
  # Totals from before countriesByDay existed; the frontend no longer writes
  # it, so it only holds that undated history.
  field :countries, type: Hash, default: {}, as: :legacy_countries
  # Totals from before devicesByDay and referrersByDay existed; no longer
  # written either, so they only hold that undated history.
  field :devices, type: Hash, default: {}, as: :legacy_devices
  field :referrers, type: Hash, default: {}, as: :legacy_referrers
  # Daily totals from before countriesByDay existed; no longer written either.
  field :viewsByDay, type: Hash, default: {}, as: :legacy_views_by_day
  field :countriesByDay, type: Hash, default: {}, as: :countries_by_day
  field :devicesByDay, type: Hash, default: {}, as: :devices_by_day
  field :referrersByDay, type: Hash, default: {}, as: :referrers_by_day
  field :uniqueVisitorCount, type: Integer, default: 0, as: :unique_visitor_count
  field :visitorCount, type: Integer, default: 0, as: :visitor_count
  field :botCount, type: Integer, default: 0, as: :bot_count
  field :createdAt, type: Time, as: :created_at
  field :updatedAt, type: Time, as: :updated_at

  # Legacy totals plus the dated breakdown, so a page's full history shows as
  # one table without the frontend storing the same counts twice.
  def countries
    all_time(legacy_countries, countries_by_day)
  end

  def devices
    all_time(legacy_devices, devices_by_day)
  end

  def referrers
    all_time(legacy_referrers, referrers_by_day)
  end

  def devices_within(period)
    within(devices_by_day, period)
  end

  def referrers_within(period)
    within(referrers_by_day, period)
  end

  # Views from before this day have no device or referrer day to fall in.
  def breakdowns_dated_since
    devices_by_day.keys.filter_map { |day| parse_day(day) }.min
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

    # The frontend only began counting views on some day, so a period
    # reaching back before it shows none rather than few.
    def first_day
      first_day_in(%w[viewsByDay countriesByDay])
    end

    # Lets traffic be analysed in a spreadsheet, beyond what the list page offers.
    def to_csv(page_views = order(visitor_count: :desc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        page_views.each do |page_view|
          csv << [
            page_view.url, page_view.visitor_count, page_view.unique_visitor_count, page_view.bot_count,
            page_view.countries.sort_by { |_, count| -count }.map { |code, count| "#{code}: #{count}" }.join("; ").presence,
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
