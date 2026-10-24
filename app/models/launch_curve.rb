# encoding: UTF-8

# A post's first weeks of views beside the median post's, so whether a new
# post is doing well is judged against the blog's own normal rather than a
# guess. Running totals, since a day's count swings too much to compare.
class LaunchCurve
  DAYS = 30
  # Fewer than this and the median is one or two posts' luck.
  MIN_POSTS = 3

  attr_reader :dates

  def initialize(page_view, entry, today: Date.current)
    @page_view = page_view
    @published = entry.published_at.to_date
    @today = today
    @dates = (@published..(@published + DAYS - 1)).to_a
  end

  # Nil past today, so a post still in its first weeks stops where it is.
  def views
    running_totals(@page_view.views_by_day).each_with_index.map { |total, index| total if @dates[index] <= @today }
  end

  def typical
    curves = others.map { |page_view, published| running_totals(page_view.views_by_day, published) }
    return if curves.size < MIN_POSTS

    curves.transpose.map { |day| median(day).round }
  end

  def typical_count
    others.size
  end

  # Each earlier entry's page and publishing day, so another measure can be
  # judged against the same entries views are.
  def peers
    others
  end

  private

  # Only posts with a full first month, published once views were being
  # counted, since earlier ones would read as weeks of nothing.
  def others
    @others ||= begin
      entries = FeedEntry.where(:published_at.lte => (@today - DAYS).end_of_day).only(:_id, :published_at)
      published = entries.to_h { |entry| [path_of(entry.url), entry.published_at.to_date] }
      page_views = PageView.where(:slug.in => published.keys - [@page_view.slug]).only(:slug, :countriesByDay, :viewsByDay).to_a
      counted_from = page_views.flat_map { |page_view| page_view.views_by_day.keys }.grep(/\A\d{4}-\d\d-\d\d\z/).min
      page_views.filter_map do |page_view|
        day = published[page_view.slug]
        [page_view, day] if counted_from && day >= Date.iso8601(counted_from)
      end
    end
  end

  def running_totals(by_day, from = @published)
    total = 0
    (from..(from + DAYS - 1)).map { |date| total += by_day[date.iso8601].to_i }
  end

  # Slugs are paths without a trailing slash, as the frontend stores them.
  def path_of(url)
    path = URI.parse(url).path.chomp("/")
    path.empty? ? "/" : path
  rescue URI::InvalidURIError
    url
  end

  def median(values)
    sorted = values.sort
    (sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0
  end
end
