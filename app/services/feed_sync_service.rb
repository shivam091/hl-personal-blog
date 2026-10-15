# encoding: UTF-8

# Exists so new posts show up and edits are picked up without entering them
# by hand. Entries missing from the feed are kept, since an entry dropping out
# of the feed is worth noticing rather than silently forgetting.
class FeedSyncService
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 20
  URL_ENV = "ATOM_FEED_URL"
  TYPE_SCHEME = "urn:taxonomy:type"
  TAG_SCHEME = "urn:taxonomy:tag"
  CATEGORY_SCHEME = "urn:taxonomy:category"

  class << self
    def call(...)
      new(...).call
    end
  end

  # `connection` is injectable so specs never fetch the real feed. The env
  # var wins so a deploy can point at another feed without re-encrypting
  # credentials.
  def initialize(url: ENV[URL_ENV].presence || Blog.atom_feed_url, connection: nil)
    @url = url
    @connection = connection
  end

  def call
    result = SyncResult.empty
    return result.tap { result.errors << "No feed URL configured (#{URL_ENV} or credentials blog.url)" } if @url.blank?

    FeedEntry.import(feed_sources, result)
  rescue Faraday::Error, Nokogiri::XML::SyntaxError => e
    result.errors << "Couldn't read #{@url}: #{e.message}"
    result
  end

  private

  def feed_sources
    document = Nokogiri::XML(connection.get(@url).body) { |config| config.strict }
    # Atom puts everything in a namespace; it adds nothing for reading.
    document.remove_namespaces!

    document.xpath("/feed/entry").map do |entry|
      url = text(entry, "id")
      FeedEntry::Source.new(
        label: url || "Entry without an id",
        url: url,
        name: text(entry, "title"),
        # The summary is cut short for feed readers; the content isn't.
        description: text(entry, "content") || text(entry, "summary"),
        type: terms(entry, TYPE_SCHEME).first,
        published_at: parse_time(text(entry, "published")),
        last_modified_at: parse_time(text(entry, "updated")),
        tags: terms(entry, TAG_SCHEME),
        categories: terms(entry, CATEGORY_SCHEME)
      )
    end
  end

  def text(entry, name)
    entry.at_xpath(name)&.text&.strip.presence
  end

  def terms(entry, scheme)
    entry.xpath("category[@scheme=$scheme]", nil, scheme: scheme).filter_map { |category| category["term"]&.strip.presence }
  end

  # Truncated to the millisecond MongoDB stores, so an unchanged date isn't
  # seen as an update. An unreadable one becomes blank rather than raising,
  # so it's reported with the entry's other errors.
  def parse_time(value)
    Time.iso8601(value).floor(3) if value
  rescue ArgumentError
    nil
  end

  def connection
    @connection ||= Faraday.new(
      headers: {"Accept" => "application/atom+xml, application/xml", "User-Agent" => "harshal-ladhe-backend feed sync"},
      request: {open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT}
    ) do |faraday|
      faraday.use ExternalCallRecorder, service: "Atom feed"
      faraday.response :raise_error
    end
  end
end
