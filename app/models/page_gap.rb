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
