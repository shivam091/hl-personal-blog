# encoding: UTF-8

# Google Analytics saw readers for months before the blog counted its own
# views, so those days are estimated from it, scaled by how the blog's counts
# compare with GA's on the days both have. Devices and referrers are split the
# way GA splits each page's day, over the views estimated for it.
class PageViewBackfill
  # The first day the blog counted its own views.
  COUNTED_FROM = Date.new(2026, 10, 10)
  # The first day the blog dated devices and referrers, a couple of days after
  # it began counting views.
  BREAKDOWNS_FROM = Date.new(2026, 10, 12)
  # Marks the visitor markers written here, so they can be told from real ones
  # and removed again.
  MARKER_PREFIX = "backfill:"
  # A day the blog counted far more than GA is bots, which GA filters out, and
  # would inflate the factors.
  BOT_DAY_RATIO = 2

  Result = Struct.new(:views_factor, :visitors_factor, :pages, :days, :views, :visitors, :skipped_views, :breakdown_days, :by_month, keyword_init: true)

  # Spreads rounding error forward, so the rounded counts still add up to the
  # scaled total instead of every small count rounding the same way.
  class Rounder
    def initialize
      @carry = 0.0
    end

    def round(value)
      total = value + @carry
      rounded = total.round
      @carry = total - rounded
      rounded
    end
  end

  def self.call(write: false)
    new.call(write: write)
  end

  def self.revert
    new.revert
  end

  def call(write: false)
    # Days that rounded to no views leave nothing behind, so a second run
    # would estimate them again and add to the first.
    raise "Already backfilled; run page_views:unbackfill first" if PageViewSeen.where(ipHash: /\A#{MARKER_PREFIX}/).exists?

    ga = ga_rows
    views_factor, visitors_factor = factors(ga)
    pages = PageView.pluck(:slug).to_set
    known, unknown = ga.select { |row| row.date.to_date < COUNTED_FROM }.partition { |row| pages.include?(row.page_path) }
    taken = counted_days
    cells = estimate(known.reject { |row| taken.include?([row.page_path, day_of(row)]) }, views_factor, visitors_factor)
    breakdowns = breakdowns_for(cells)
    save(cells, breakdowns) if write

    Result.new(breakdown_days: breakdowns.size, views_factor: views_factor, visitors_factor: visitors_factor, pages: cells.map { |cell| cell[:slug] }.uniq.size,
      days: cells.map { |cell| [cell[:slug], cell[:day]] }.uniq.size, views: cells.sum { |cell| cell[:views] },
      visitors: cells.sum { |cell| cell[:visitors] }, skipped_views: unknown.sum(&:views),
      by_month: cells.each_with_object(Hash.new { |hash, month| hash[month] = {views: 0, visitors: 0} }) do |cell, months|
        months[cell[:day][0, 7]][:views] += cell[:views]
        months[cell[:day][0, 7]][:visitors] += cell[:visitors]
      end.sort.to_h)
  end

  # Everything before the blog's own counting is backfilled by construction,
  # so it goes entirely.
  def revert
    PageView.only(:slug, :countriesByDay, :devicesByDay, :referrersByDay).each do |page_view|
      counted = page_view.countries_by_day.select { |day, _| day < COUNTED_FROM.iso8601 }
      unset = counted.keys.map { |day| "countriesByDay.#{day}" } +
        page_view.devices_by_day.keys.select { |day| day < BREAKDOWNS_FROM.iso8601 }.map { |day| "devicesByDay.#{day}" } +
        page_view.referrers_by_day.keys.select { |day| day < BREAKDOWNS_FROM.iso8601 }.map { |day| "referrersByDay.#{day}" }
      next if unset.empty?

      markers = PageViewSeen.where(slug: page_view.slug, ipHash: /\A#{MARKER_PREFIX}/)
      update = {"$unset" => unset.to_h { |field| [field, ""] }}
      update["$inc"] = {"visitorCount" => -counted.each_value.sum { |counts| counts.values.sum(&:to_i) }, "uniqueVisitorCount" => -markers.count} if counted.any?
      PageView.collection.update_one({"slug" => page_view.slug}, update)
    end
    PageViewSeen.collection.delete_many("ipHash" => {"$regex" => "\\A#{MARKER_PREFIX}"})
  end

  private

  def ga_rows
    Google::Analytics::CountryStat.only(:date, :page_path, :country, :views, :active_users).order(date: :asc, page_path: :asc, country: :asc).to_a
  end

  def day_of(row)
    row.date.to_date.iso8601
  end

  # Both factors from the days the blog and GA overlap and it wasn't being
  # hit by bots, over pages the blog has a record of.
  def factors(ga)
    pages = PageView.pluck(:slug).to_set
    overlap = ga.select { |row| row.date.to_date >= COUNTED_FROM && pages.include?(row.page_path) }.group_by { |row| day_of(row) }
    blog_views = Hash.new(0)
    PageView.only(:countriesByDay).each { |page_view| page_view.countries_by_day.each { |day, counts| blog_views[day] += counts.values.sum(&:to_i) } }
    blog_visitors = PageViewSeen.collection.aggregate([{"$group" => {"_id" => "$day", "n" => {"$sum" => 1}}}]).to_h { |row| [row["_id"], row["n"]] }

    usable = overlap.select { |day, rows| blog_views[day].positive? && blog_views[day] <= BOT_DAY_RATIO * rows.sum(&:views) }
    raise "No days where both the blog and Google Analytics have views to compare" if usable.empty?

    [usable.sum { |day, _| blog_views[day] }.fdiv(usable.sum { |_, rows| rows.sum(&:views) }),
      usable.sum { |day, _| blog_visitors[day].to_i }.fdiv(usable.sum { |_, rows| rows.sum(&:active_users) })]
  end

  def counted_days
    PageView.only(:slug, :countriesByDay, :viewsByDay).each_with_object(Set.new) do |page_view, days|
      (page_view.countries_by_day.keys + page_view.legacy_views_by_day.keys).each { |day| days << [page_view.slug, day] }
    end
  end

  def estimate(rows, views_factor, visitors_factor)
    view_rounder, visitor_rounder = Rounder.new, Rounder.new
    rows.filter_map do |row|
      views = view_rounder.round(row.views * views_factor)
      # A visitor viewed at least once, and a country with no views has none.
      visitors = [visitor_rounder.round(row.active_users * visitors_factor), views].min
      {slug: row.page_path, day: day_of(row), country: row.country, views: views, visitors: visitors} if views.positive?
    end
  end

  def save(cells, breakdowns)
    cells.group_by { |cell| cell[:slug] }.each do |slug, page_cells|
      by_day = page_cells.group_by { |cell| cell[:day] }.transform_values { |day_cells| day_cells.to_h { |cell| [cell[:country], cell[:views]] } }
      PageView.collection.update_one({"slug" => slug},
        {"$set" => by_day.to_h { |day, counts| ["countriesByDay.#{day}", counts] },
         "$inc" => {"visitorCount" => page_cells.sum { |cell| cell[:views] }, "uniqueVisitorCount" => page_cells.sum { |cell| cell[:visitors] }}})
    end
    breakdowns.group_by { |(slug, _), _| slug }.each do |slug, days|
      PageView.collection.update_one({"slug" => slug}, {"$set" => days.each_with_object({}) do |((_, day), split), fields|
        fields["devicesByDay.#{day}"] = split[:devices] if split[:devices].any?
        fields["referrersByDay.#{day}"] = split[:referrers] if split[:referrers].any?
      end})
    end
    PageViewSeen.collection.insert_many(cells.flat_map { |cell| markers(cell) }) if cells.any? { |cell| cell[:visitors].positive? }
  end

  # Each page day's views to split: the ones estimated, and the blog's own on
  # the days before it dated devices and referrers.
  def breakdowns_for(cells)
    totals = Hash.new(0)
    cells.each { |cell| totals[[cell[:slug], cell[:day]]] += cell[:views] }
    PageView.only(:slug, :countriesByDay, :devicesByDay, :referrersByDay).each do |page_view|
      page_view.countries_by_day.each do |day, counts|
        next unless day >= COUNTED_FROM.iso8601 && day < BREAKDOWNS_FROM.iso8601 && !page_view.devices_by_day.key?(day) && !page_view.referrers_by_day.key?(day)

        totals[[page_view.slug, day]] += counts.values.sum(&:to_i)
      end
    end

    devices = grouped_views(Google::Analytics::DeviceStat, totals) { |row| row.device }
    hosts = PageView.only(:slug, :url).to_h { |page_view| [page_view.slug, host_of(page_view.url)] }
    referrers = grouped_views(Google::Analytics::ReferrerStat, totals) { |row| referrer_key(row.referrer, hosts[row.page_path]) }
    totals.to_h do |key, total|
      [key, {devices: allocate(total, devices[key] || {}), referrers: allocate(total, referrers[key] || {})}]
    end.reject { |_, split| split.values.all?(&:empty?) }
  end

  def grouped_views(model, totals)
    model.where(:date.lt => BREAKDOWNS_FROM.to_time(:utc)).each_with_object({}) do |row, grouped|
      key = [row.page_path, day_of(row)]
      next unless totals.key?(key)

      counts = (grouped[key] ||= Hash.new(0))
      counts[yield(row)] += row.views
    end
  end

  # As the blog keys a referrer: its host without www, dots swapped out of the
  # name, and its own pages as internal.
  def referrer_key(referrer, own_host)
    return "direct" if referrer.blank? || referrer == "(not set)"

    host = host_of(referrer)
    return "direct" if host.blank?

    host == own_host ? "internal" : host.gsub(/[.$]/, "_")[0, 64]
  end

  def host_of(url)
    URI.parse(url.to_s).host.to_s.downcase.delete_prefix("www.")
  rescue URI::InvalidURIError
    ""
  end

  # Largest remainder, so the split adds up to exactly the views it divides.
  def allocate(total, weights)
    sum = weights.values.sum
    return {} if sum.zero? || total.zero?

    exact = weights.transform_values { |weight| total * weight.fdiv(sum) }
    split = exact.transform_values(&:floor)
    exact.sort_by { |key, value| [-(value - value.floor), key] }.first(total - split.values.sum).each { |key, _| split[key] += 1 }
    split.reject { |_, count| count.zero? }
  end

  def markers(cell)
    at = Time.utc(*cell[:day].split("-").map(&:to_i), 12)
    Array.new(cell[:visitors]) do |index|
      {"slug" => cell[:slug], "day" => cell[:day], "country" => cell[:country], "at" => at,
       "ipHash" => "#{MARKER_PREFIX}#{Digest::MD5.hexdigest([cell[:slug], cell[:day], cell[:country], index].join("|"))}"}
    end
  end
end
