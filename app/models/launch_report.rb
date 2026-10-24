# encoding: UTF-8

# How an entry did over its first days against the blog's typical entry at
# the same age, so a launch that's lagging is noticed while there's still
# time to share it again, and one that's flying is known to be worth
# following up.
class LaunchReport
  # A week says how the launch went; a month, whether it kept going.
  AGES = [7, 30].freeze
  # Within this share of typical either way, an entry reads as typical, so
  # ordinary scatter isn't called a hit or a miss.
  TYPICAL_BAND = 0.2

  Measure = Struct.new(:label, :value, :typical, :settled, keyword_init: true) do
    def ratio
      value.fdiv(typical) if typical&.positive?
    end

    def verdict
      return if ratio.nil?

      if ratio >= 1 + TYPICAL_BAND then :above
      elsif ratio <= 1 - TYPICAL_BAND then :below
      else :typical
      end
    end
  end

  attr_reader :entry, :age, :path

  def initialize(entry, age, today: Date.current)
    @entry = entry
    @age = age
    @today = today
    @published = entry.published_at.in_time_zone.to_date
    @path = IndexCoverage.path_of(entry.url)
    @slug = slug_of(@path)
  end

  def days
    @published..(@published + age - 1)
  end

  def measures
    @measures ||= [views, likes, search_clicks, analytics_views]
  end

  def summary
    views = measures.first
    case views.verdict
    when :above then "ahead of the typical entry"
    when :below then "behind the typical entry"
    when :typical then "about as read as the typical entry"
    else "too few earlier entries to compare with"
    end
  end

  private

  def curve
    @curve ||= LaunchCurve.new(PageView.where(_id: @slug).first || PageView.new(slug: @slug), entry, today: @today)
  end

  # Peers by the path Search Console and Analytics name them by, beside the
  # day each was published.
  def peers
    @peers ||= curve.peers.map { |page_view, published| [page_view.slug, published] }
  end

  def views
    typical = curve.typical
    Measure.new(label: "Views", value: curve.views[age - 1].to_i, typical: typical&.fetch(age - 1), settled: true)
  end

  def likes
    by_slug = PageLike.where(:slug.in => [@slug, *peers.map(&:first)]).only(:slug, :countriesByDay).index_by(&:slug)
    total = ->(slug, published) { window(published).sum { |date| by_slug[slug]&.likes_by_day&.fetch(date.iso8601, 0).to_i } }
    Measure.new(label: "Likes", value: total.(@slug, @published), typical: typical(peers.map { |slug, published| total.(slug, published) }),
      settled: true)
  end

  def search_clicks
    daily_measure("Search clicks", :clicks, Google::SearchConsole::Stat.page_totals)
  end

  def analytics_views
    daily_measure("Analytics views", :views, Google::Analytics::Stat.all)
  end

  # Peers published before a source was first synced would read as having
  # had none, so only those it covered from their first day count. Not
  # settled while the source hasn't reached the window's last day, as
  # Google fills in recent days late. Paths are asked for with and without
  # a trailing slash, since Google names a page however it was linked.
  def daily_measure(label, field, scope)
    first, last = scope.min(:date)&.to_date, scope.max(:date)&.to_date
    covered = first ? peers.select { |_, published| published >= first } : []
    paths = [@slug, *covered.map(&:first)].flat_map { |slug| [slug, "#{slug.chomp("/")}/"] }.uniq
    from = [@published, *covered.map(&:last)].min
    rows = scope.klass.grouped(scope.where(:page_path.in => paths, date: from..days.last), by: %i[page_path date]).to_a
    totals = rows.each_with_object(Hash.new(0)) { |row, sums| sums[[slug_of(row[:page_path]), row[:date].to_date]] += row.value(field).to_i }
    total = ->(slug, published) { window(published).sum { |date| totals[[slug, date]] } }
    Measure.new(label: label, value: total.(@slug, @published), typical: typical(covered.map { |slug, published| total.(slug, published) }),
      settled: last.present? && last >= days.last)
  end

  def window(published)
    published..(published + age - 1)
  end

  def typical(values)
    return if values.size < LaunchCurve::MIN_POSTS

    sorted = values.sort
    ((sorted[(sorted.size - 1) / 2] + sorted[sorted.size / 2]) / 2.0).round
  end

  # Page views key pages without a trailing slash, as the blog stores them.
  def slug_of(path)
    path.to_s.chomp("/").presence || "/"
  end
end
