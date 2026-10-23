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
  NO_CAMPAIGN_PART = "(none)"

  Campaign = Struct.new(:source, :medium, :name, :content, :term, :id)

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
  field :campaignsByDay, type: Hash, default: {}, as: :campaigns_by_day
  # Absent on pages counted before the frontend recorded consent, so it defaults to empty rather than to all unset.
  field :consentByDay, type: Hash, default: {}, as: :consent_by_day
  # Whether gtag loaded is the one sign of a blocker, which GA can't report itself; a view in
  # neither tally left before it could be told.
  field :gaByDay, type: Hash, default: {}, as: :ga_by_day
  # Webdriver views are already left out as bots while datacentre ones stay in the human counts,
  # so only datacentre traffic is left to explain part of GA's gap.
  field :suspectByDay, type: Hash, default: {}, as: :suspect_by_day
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

  def campaigns_within(period)
    within(campaigns_by_day, period)
  end

  # Cut to the period like the page's other breakdowns, so its consent split lines up with them.
  def consent_within(period)
    within(consent_by_day, period)
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

    # Every page's together, by ISO day, since GA's views are compared with them
    # day by day; days from before consent was recorded are absent.
    def consent_daily(period)
      daily_totals(:consentByDay, period)
    end

    # Same shape as consent_daily; days from before gtag's loading was recorded are absent.
    def ga_daily(period)
      daily_totals(:gaByDay, period)
    end

    # Same shape again; days from before automation signals were recorded are absent.
    def suspect_daily(period)
      daily_totals(:suspectByDay, period)
    end

    # Each field began on its own day, so the report keeps them apart to say which days it can trust.
    def ga_first_day
      first_day_in(%w[gaByDay])
    end

    def suspect_first_day
      first_day_in(%w[suspectByDay])
    end

    # Per page, over the days given only, since GA's views are known for some days alone; a
    # page counted before dated totals existed comes in through views_by_day too.
    def views_by_slug(days)
      only(:slug, :countriesByDay, :viewsByDay).each_with_object(Hash.new(0)) do |page_view, totals|
        page_view.views_by_day.each { |day, count| totals[page_view.slug] += count if days.include?(day) }
      end
    end

    # Views were only split by consent from some day, so a period reaching back
    # before it covers fewer views than it seems to.
    def consent_first_day
      first_day_in(%w[consentByDay])
    end

    # One routine for every by-day tally, so consent, tag loading and automation are cut to a
    # period the same way.
    def daily_totals(field, period)
      from, to = period.from.iso8601, period.to.iso8601
      only(field).each_with_object(Hash.new { |hash, day| hash[day] = Hash.new(0) }) do |page_view, days|
        page_view.public_send(field).each do |day, counts|
          counts.each { |key, count| days[day][key] += count.to_i } if day.between?(from, to)
        end
      end
    end

    # Every page's together, as a campaign's link can land anywhere.
    def campaigns_within(period)
      only(:campaignsByDay).each_with_object(Hash.new(0)) do |page_view, totals|
        page_view.campaigns_within(period).each { |key, count| totals[key] += count }
      end
    end

    # The blog's safeKey swaps dots for underscores, which can't be swapped
    # back here, since campaign names have underscores of their own; and it
    # cuts a key at 256 characters, so a long one can lose its later parts.
    # Keys counted before content, term and id were kept have only the
    # first three parts.
    def campaign(key)
      parts = key.to_s.split("|", Campaign.members.size)
      Campaign.new(*Campaign.members.each_index.map { |index| parts[index].presence || NO_CAMPAIGN_PART })
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
