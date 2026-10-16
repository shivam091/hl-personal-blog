# encoding: UTF-8

class IndexCoverage
  # Edged at the usual "refresh it" checkpoints, so a bucket says which
  # pages are due.
  AGE_BUCKETS = {"Under 30 days" => 0...30, "30–90 days" => 30...90, "90–180 days" => 90...180,
                 "180–365 days" => 180...365, "Over a year" => 365..}.freeze

  # Spans in which Google usually gets round to a page, so a bucket past
  # them says the wait is no longer normal.
  WAIT_BUCKETS = {"Under a week" => 0...7, "1–4 weeks" => 7...28, "1–3 months" => 28...90, "Over 3 months" => 90..}.freeze

  Waiting = Struct.new(:page, :days, :requested, keyword_init: true)

  # Google recrawls a page it thinks is changing within weeks; past these
  # its copy is likely older than the page.
  CRAWL_BUCKETS = {"Under a week" => 0...7, "1–4 weeks" => 7...28, "1–3 months" => 28...90, "Over 3 months" => 90..}.freeze
  NEVER_CRAWLED = "Never crawled"

  Stale = Struct.new(:page, :crawled_at, :changed_at, keyword_init: true)

  def initialize(today: Date.current)
    @today = today
  end

  def total
    @total ||= CrawledPage.count
  end

  def indexed
    @indexed ||= CrawledPage.indexed.count
  end

  def any?
    total.positive?
  end

  # Search Console's own verdicts, which say why a page isn't indexed.
  def verdicts
    Google::SearchConsole::UrlInspection.pluck(:verdict).map { |verdict| verdict.presence || "NEUTRAL" }.tally
  end

  # Most recently changed first, since a new or updated post missing from the
  # index is the one costing traffic now.
  def not_indexed(limit: 10)
    CrawledPage.not_indexed.order(last_modified_at: :desc).limit(limit)
  end

  def ages
    dates = CrawledPage.pluck(:last_modified_at).compact.map { |time| (@today - time.to_date).to_i }
    AGE_BUCKETS.transform_values { |range| dates.count { |days| range.cover?(days) } }
  end

  # From the request to index a page when one was made, otherwise from the
  # page's last change, since that's when Google could first have seen it.
  # Longest first, as those are the ones Google may have passed over.
  def waiting
    @waiting ||= CrawledPage.not_indexed.only(:url, :last_modified_at, :index_requested_at).filter_map do |page|
      since = page.index_requested_at || page.last_modified_at
      Waiting.new(page: page, days: (@today - since.to_date).to_i, requested: page.index_requested_at.present?) if since
    end.sort_by { |row| [-row.days, row.page.url] }
  end

  def waiting_ages
    WAIT_BUCKETS.transform_values { |range| waiting.count { |row| range.cover?(row.days) } }
  end

  # Newest first, as a new entry the sitemap hasn't picked up is the one
  # Google can't find yet.
  def entries_missing_from_sitemap
    paths = crawled_paths.map { |path| path.chomp("/") }.to_set
    FeedEntry.order(published_at: :desc).only(:_id, :name, :published_at).reject { |entry| paths.include?(path_of(entry.url).to_s.chomp("/")) }
  end

  # Only under an entry type's path, since tag, category and listing pages
  # are in the sitemap but never in the feed. One here is usually an entry
  # renamed or taken down whose old address the sitemap still offers.
  def sitemap_entries_missing_from_feed
    paths = FeedEntry.pluck(:_id).filter_map { |url| path_of(url)&.chomp("/") }.to_set
    sections = FeedEntry::TYPES.map { |type| "/#{type}/" }
    CrawledPage.order(url: :asc).only(:url, :indexed).select do |page|
      path = path_of(page.url)
      path&.start_with?(*sections) && !paths.include?(path.chomp("/"))
    end
  end

  # Inspected pages only, as only an inspection says when Google last came;
  # one it never came to gets its own bucket rather than counting as old.
  def crawl_ages
    ages = inspections.map { |inspection| inspection.last_crawled_at && (@today - inspection.last_crawled_at.to_date).to_i }
    CRAWL_BUCKETS.transform_values { |range| ages.count { |days| days && range.cover?(days) } }.merge(NEVER_CRAWLED => ages.count(&:nil?))
  end

  def inspected?
    inspections.any?
  end

  # Changed since Google last crawled them, so search still shows the old
  # page; most read first, since that's where the old copy costs most.
  def changed_since_crawl(views = {})
    inspections.filter_map do |inspection|
      page = inspection.crawled_page
      next unless page&.last_modified_at && inspection.last_crawled_at && page.last_modified_at > inspection.last_crawled_at

      Stale.new(page: page, crawled_at: inspection.last_crawled_at, changed_at: page.last_modified_at)
    end.sort_by { |row| [-views.fetch(path_of(row.page.url), 0), row.crawled_at, row.page.url] }
  end

  # Paths, so pages join with the blog's own and Google's figures.
  def indexed_paths
    @indexed_paths ||= CrawledPage.indexed.pluck(:url).filter_map { |url| path_of(url) }.to_set
  end

  def crawled_paths
    @crawled_paths ||= CrawledPage.pluck(:url).filter_map { |url| path_of(url) }.to_set
  end

  class << self
    def path_of(url)
      URI.parse(url.to_s).path.presence || "/"
    rescue URI::InvalidURIError
      nil
    end
  end

  private

  def inspections
    @inspections ||= Google::SearchConsole::UrlInspection.includes(:crawled_page).only(:last_crawled_at, :crawled_page_id).to_a
  end

  def path_of(url)
    self.class.path_of(url)
  end
end
