# encoding: UTF-8

# The blog's own view counts set against GA's, page by page, so it's known
# how far GA's figures can be trusted.
class ViewComparison
  CSV_HEADERS = ["Page", "Blog views", "GA views", "Difference"].freeze

  def initialize(blog_stats, analytics, within: nil)
    @blog_stats = blog_stats
    @analytics = analytics
    @within = within
  end

  # Nil unless a comparison is picked and either source counted something in
  # the days compared with, since every page would otherwise read as new.
  def previous
    return @previous if defined?(@previous)

    period = @blog_stats.period
    earlier = self.class.new(@blog_stats, @analytics, within: period.previous) if period.compare? && !@within
    @previous = (earlier if earlier&.rows&.any?)
  end

  def previous_by_path
    @previous_by_path ||= previous&.rows&.to_h { |path, blog, google, difference| [path, [blog, google, difference]] }
  end

  # The difference is a share of the blog's own count, so a small page losing
  # views to ad blockers or bot filtering shows as clearly as a big one.
  # Busiest first, so the gaps that cost the most views lead.
  def rows
    @rows ||= begin
      within = @within || @blog_stats.period
      own = @blog_stats.by_page(:views, within)
      ga = @analytics.pages(within).transform_values(&:views)
      (own.keys | ga.keys).map do |path|
        blog = own.fetch(path, 0)
        google = ga.fetch(path, 0)
        [path, blog, google, (google.fdiv(blog) - 1 if blog.positive?)]
      end.sort_by { |path, blog, google, _| [-[blog, google].max, path] }
    end
  end

  def to_csv
    CSV.generate do |csv|
      csv << [*CSV_HEADERS, *("Difference before" if previous)]
      rows.each do |path, blog, google, difference|
        before = previous_by_path&.[](path) || []
        csv << [path, CompareChange.cell(blog, before[0], compare: !previous.nil?), CompareChange.cell(google, before[1], compare: !previous.nil?),
          difference&.round(4), *(before[2]&.round(4) if previous)]
      end
    end
  end
end
