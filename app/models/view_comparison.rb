# encoding: UTF-8

# The blog's own view counts set against GA's, page by page, so it's known
# how far GA's figures can be trusted.
class ViewComparison
  CSV_HEADERS = ["Page", "Blog views", "GA views", "Difference"].freeze

  def initialize(blog_stats, analytics)
    @blog_stats = blog_stats
    @analytics = analytics
  end

  # The difference is a share of the blog's own count, so a small page losing
  # views to ad blockers or bot filtering shows as clearly as a big one.
  # Busiest first, so the gaps that cost the most views lead.
  def rows
    @rows ||= begin
      own = @blog_stats.by_page(:views)
      ga = @analytics.pages.transform_values(&:views)
      (own.keys | ga.keys).map do |path|
        blog = own.fetch(path, 0)
        google = ga.fetch(path, 0)
        [path, blog, google, (google.fdiv(blog) - 1 if blog.positive?)]
      end.sort_by { |path, blog, google, _| [-[blog, google].max, path] }
    end
  end

  def to_csv
    CSV.generate do |csv|
      csv << CSV_HEADERS
      rows.each do |path, blog, google, difference|
        csv << [path, blog, google, difference&.round(4)]
      end
    end
  end
end
