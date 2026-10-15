# encoding: UTF-8

# Exists so new posts show up and last-modified dates stay current without
# entering them by hand.
# Indexed status is left alone: only Google's crawl report knows it. Pages
# missing from the sitemap are kept, since a page dropping out of the
# sitemap is worth noticing rather than silently forgetting.
class SitemapSyncService
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  # A sitemap index can point at other sitemaps; this bounds a misconfigured
  # or looping index.
  MAX_SITEMAPS = 50

  class << self
    def call(...)
      new(...).call
    end
  end

  # `connection` is injectable so specs never fetch the real sitemap.
  def initialize(url: Rails.application.credentials.dig(:sitemap, :url), connection: nil)
    @url = url
    @connection = connection
  end

  def call
    result = SyncResult.empty
    return result.tap { result.errors << "No sitemap URL configured (credentials sitemap.url)" } if @url.blank?

    entries = sitemap_entries(@url)
    # One query up front instead of one per URL.
    pages = CrawledPage.where(:url.in => entries.map(&:first)).index_by(&:url)

    entries.each do |url, lastmod|
      sync_page(pages[url] || CrawledPage.new(url: url), lastmod, result)
    end
    result
  rescue Faraday::Error, Nokogiri::XML::SyntaxError => e
    result.errors << "Couldn't read #{@url}: #{e.message}"
    result
  end

  private

  def sync_page(page, lastmod, result)
    page.last_modified_at = lastmod if lastmod
    return result.unchanged += 1 unless page.new_record? || page.changed?

    outcome = page.new_record? ? :created : :updated
    if page.save
      result[outcome] += 1
    else
      result.errors << "#{page.url}: #{page.errors.full_messages.to_sentence}"
    end
  end

  # Flattened across a sitemap index, since the blog may split its sitemap
  # into several files as it grows.
  def sitemap_entries(url, fetched = [0])
    fetched[0] += 1
    raise Faraday::Error, "more than #{MAX_SITEMAPS} sitemaps" if fetched[0] > MAX_SITEMAPS

    document = Nokogiri::XML(connection.get(url).body) { |config| config.strict }
    # Sitemaps put everything in a namespace; it adds nothing for reading.
    document.remove_namespaces!

    if document.root&.name == "sitemapindex"
      document.xpath("//sitemap/loc").flat_map { |loc| sitemap_entries(loc.text.strip, fetched) }
    else
      document.xpath("//url").filter_map do |node|
        loc = node.at_xpath("loc")&.text&.strip
        [loc, parse_lastmod(node.at_xpath("lastmod")&.text)] if loc.present?
      end
    end
  end

  # W3C dates may be just a day or a full timestamp. Truncated to the
  # millisecond MongoDB stores, so an unchanged date isn't seen as an update.
  def parse_lastmod(value)
    DateTime.iso8601(value.strip).to_time.floor(3) if value.present?
  rescue Date::Error
    nil
  end

  def connection
    @connection ||= Faraday.new(
      headers: {"Accept" => "application/xml", "User-Agent" => "harshal-ladhe-backend sitemap sync"},
      request: {open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT}
    ) do |faraday|
      faraday.use ExternalCallRecorder, service: "Blog sitemap"
      faraday.response :raise_error
    end
  end
end
