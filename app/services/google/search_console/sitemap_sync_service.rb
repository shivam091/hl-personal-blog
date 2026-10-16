# encoding: UTF-8

module Google
  module SearchConsole
    # Sitemaps no longer listed are kept, since one dropping out of Search
    # Console is worth noticing rather than forgetting.
    class SitemapSyncService
      LIST_URL = "https://searchconsole.googleapis.com/webmasters/v3/sites/%{site}/sitemaps"

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(options = {})
        @site = options.fetch(:site) { Rails.application.credentials.dig(:google, :search_console_site) }
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        return result.tap { result.errors << "No Search Console site configured (credentials google.search_console_site)" } if @site.blank?

        synced = SyncLock.hold("google/search_console/sitemaps") do
          listed = @client.get(format(LIST_URL, site: ERB::Util.url_encode(@site))).fetch("sitemap", [])
          sitemaps = Sitemap.where(:path.in => listed.map { |entry| entry["path"] }).index_by(&:path)
          synced_at = Time.current
          listed.each do |entry|
            sitemap = sitemaps[entry["path"]] || Sitemap.new(path: entry["path"])
            sync_sitemap(sitemap, entry, result)
            SitemapHistory.record(sitemap, synced_at: synced_at) if sitemap.persisted?
          end
        end
        result.errors << "Search Console sitemaps: another sync is already running, so this one was skipped" unless synced
        result
      rescue ApiClient::Error => e
        result.errors << "Search Console sitemaps: #{e.message}"
        result
      end

      private

      def sync_sitemap(sitemap, entry, result)
        sitemap.assign_attributes(
          sitemap_type: entry["type"],
          pending: entry["isPending"] == true,
          sitemaps_index: entry["isSitemapsIndex"] == true,
          last_submitted_at: parse_time(entry["lastSubmitted"]),
          last_downloaded_at: parse_time(entry["lastDownloaded"]),
          # Counts come as strings, since they're 64-bit in the API.
          error_count: entry["errors"].to_i,
          warning_count: entry["warnings"].to_i,
          # "indexed" is left out: Google has deprecated it and no longer fills it.
          contents: Array(entry["contents"]).map { |content| {"type" => content["type"], "submitted" => content["submitted"].to_i} }
        )
        return result.unchanged += 1 unless sitemap.new_record? || sitemap.changed?

        outcome = sitemap.new_record? ? :created : :updated
        if sitemap.save
          result[outcome] += 1
        else
          result.errors << "#{sitemap.path}: #{sitemap.errors.full_messages.to_sentence}"
        end
      end

      # Truncated to the millisecond MongoDB stores, so an unchanged time isn't
      # seen as an update.
      def parse_time(value)
        Time.iso8601(value).floor(3) if value.present?
      rescue ArgumentError
        nil
      end
    end
  end
end
