# encoding: UTF-8

require "csv"

# Each page's views counted by the blog against GA's for a period, since a page missing far more than
# the rest points to something wrong on it rather than to readers' choices.
class PageGap
  # Below this many views a page's share lost is a few readers.
  MIN_VIEWS = 20
  # In points of its share lost above the site's median, which is where a page stops being ordinary: readers
  # who decline or block lose every page alike, so a page well above is losing views for a reason of its own.
  MARGIN = 0.2
  # Enough pages to show where the missing views go without the chart running down the page.
  TOP_MISSING = 15

  Row = Struct.new(:slug, :first_party, :analytics, :flagged, keyword_init: true) do
    def gap
      first_party - analytics
    end

    # Nil on a page too quiet to judge, and on one GA counted that the blog didn't.
    def percent
      gap.fdiv(first_party) if first_party >= MIN_VIEWS
    end
  end

  attr_reader :period

  def initialize(period, analytics: Google::Analytics::Summary.new(period))
    @period = period
    @analytics = analytics
  end

  # Only the days GA has synced, so a day it hasn't doesn't read as every page losing its views.
  def rows
    @rows ||= begin
      counted = first_party_views
      seen = analytics_views
      pages = (counted.keys | seen.keys).map { |slug| Row.new(slug: slug, first_party: counted.fetch(slug, 0), analytics: seen.fetch(slug, 0), flagged: false) }
      middle = median(pages.filter_map(&:percent))
      pages.each { |row| row.flagged = !middle.nil? && !row.percent.nil? && row.percent >= middle + MARGIN }
      @median_percent = middle
      pages
    end
  end

  # Of the pages busy enough to judge; nil when there are none.
  def median_percent
    rows
    @median_percent
  end

  def flagged
    rows.select(&:flagged)
  end

  # The pages busy enough to have a share lost, which are the only ones the median is drawn from.
  def judged
    rows.select(&:percent)
  end

  # Most missing first, whatever their share, since a busy page losing a little can cost more views than a
  # quiet one losing most.
  def missing(limit = TOP_MISSING)
    rows.select { |row| row.gap.positive? }.sort_by { |row| [-row.gap, row.slug] }.first(limit)
  end

  # The flagged pages costing the most views, which are the ones worth looking into first.
  def top_flagged(limit = TOP_MISSING)
    flagged.sort_by { |row| [-row.gap, row.slug] }.first(limit)
  end

  # Each page's gap put down to causes by the rules the site's daily snapshot uses, worked out a day at a
  # time from the page's own tallies so a page reads like the consent report. Only the synced days with the
  # page's consent split count; a page with none is left out, as its gap can't be pinned on anything.
  def causes(slugs)
    seen = analytics_views_by_day
    PageView.where(:slug.in => slugs.to_a).each_with_object({}) do |page_view, found|
      days = synced_days.filter_map do |day|
        next unless page_view.consent_by_day[day]

        snapshot = ConsentSnapshot.compose(ConsentSnapshot::Inputs.new(
          date: Date.iso8601(day), first_party: page_view.views_by_day[day].to_i, analytics: seen.dig(page_view.slug, day).to_i,
          states: page_view.consent_by_day[day], ga: page_view.ga_by_day[day], suspects: page_view.suspect_by_day[day]
        ))
        snapshot if snapshot.complete?
      end
      found[page_view.slug] = ConsentGap.new(days) if days.any?
    end
  end

  # Only pages GA counted fewer views on, so one it counted more on can't hide views missing elsewhere.
  def missing_total
    rows.sum { |row| [row.gap, 0].max }
  end

  # Worked out once, so the chart's dashed line and the flag can't disagree; nil without a median.
  def threshold
    median_percent + MARGIN if median_percent
  end

  def any?
    @analytics.any?
  end

  def days_covered
    synced_days.size
  end

  def to_csv(rows = self.rows)
    CSV.generate do |csv|
      csv << ["Page", "Our views", "GA views", "Gap", "Gap %", "Well above the median"]
      rows.each { |row| csv << [row.slug, row.first_party, row.analytics, row.gap, row.percent&.round(4), (row.flagged ? "yes" : "no")] }
    end
  end

  private

  def synced_days
    @synced_days ||= @analytics.days_with_data.map(&:iso8601).to_set
  end

  def first_party_views
    PageView.views_by_slug(synced_days)
  end

  def analytics_views
    @analytics.pages.each_with_object(Hash.new(0)) { |(path, row), totals| totals[slug_of(path)] += row.views.to_i }
  end

  def analytics_views_by_day
    rows = Google::Analytics::Stat.where(:date.in => synced_days.map { |day| Date.iso8601(day) }).pluck(:date, :page_path, :views)
    rows.each_with_object(Hash.new { |totals, slug| totals[slug] = Hash.new(0) }) do |(date, path, views), totals|
      totals[slug_of(path)][date.to_date.iso8601] += views.to_i
    end
  end

  # The blog names a page without its trailing slash and GA by the address it was loaded at.
  def slug_of(path)
    path.to_s.sub(/[?#].*\z/, "").chomp("/").presence || "/"
  end

  def median(values)
    return if values.empty?

    sorted = values.sort
    middle = sorted.size / 2
    sorted.size.odd? ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2.0
  end
end
