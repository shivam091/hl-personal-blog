# encoding: UTF-8

# GA's share of an entry's own views over its first days, set beside its Analytics views in the launch mail,
# so an entry read mostly by readers GA can't see doesn't look like a weak launch.
class LaunchGaShare
  def initialize(slug, days)
    @slug = slug
    @days = days
  end

  # Nil when GA hasn't synced any of the days, or either side is too few views to judge, as PageGap does.
  # Only the days GA has synced count on both sides, so a day it hasn't reached doesn't read as missed.
  def share
    return @share if defined?(@share)

    @share = begin
      synced = Google::Analytics::Stat.where(date: @days.first..@days.last).distinct(:date).map { |date| date.to_date.iso8601 }.to_set
      ours = (PageView.where(_id: @slug).first&.views_by_day || {}).sum { |day, count| synced.include?(day) ? count : 0 }
      theirs = analytics_views(synced)
      theirs.fdiv(ours) if ours >= PageGap::MIN_VIEWS && theirs >= PageGap::MIN_VIEWS
    end
  end

  private

  # Every address GA loaded the page at, as it counts a page with a trailing slash or a query apart.
  def analytics_views(synced)
    return 0 if synced.empty?

    scope = Google::Analytics::Stat.where(date: @days.first..@days.last, page_path: /\A#{Regexp.escape(@slug.chomp("/"))}\/?(?:[?#]|\z)/)
    Google::Analytics::Stat.grouped(scope, by: [:page_path]).sum { |row| PageGapShift.slug_of(row[:page_path]) == @slug ? row.views.to_i : 0 }
  end
end
