# encoding: UTF-8

module Google
  module SearchConsole
    # Through Search Console, since Google's sitemap ping endpoint is gone
    # (retired in 2023). Resubmitting an unchanged sitemap does no harm, so
    # it's sent after every blog sync rather than only when something is new.
    #
    # Setup: the service account must be an Owner or Full user of the
    # property (Search Console → Settings → Users and permissions), since
    # submitting is a write and needs the full webmasters scope.
    class SitemapSubmitService
      SCOPE = "https://www.googleapis.com/auth/webmasters"
      SUBMIT_URL = "https://searchconsole.googleapis.com/webmasters/v3/sites/%{site}/sitemaps/%{sitemap}"

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(options = {})
        @site = options.fetch(:site) { Rails.application.credentials.dig(:google, :search_console_site) }
        @sitemap = options.fetch(:sitemap) { Blog.sitemap_url }
        @client = options.fetch(:client) { ApiClient.new(scope: SCOPE) }
        @refresh = options.fetch(:refresh, SitemapSyncService)
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        if @site.blank?
          return result.tap { result.errors << "No Search Console site configured (credentials google.search_console_site)" }
        end
        return result.tap { result.errors << "No sitemap configured (credentials blog.url)" } if @sitemap.blank?

        @client.put(format(SUBMIT_URL, site: ERB::Util.url_encode(@site), sitemap: ERB::Util.url_encode(@sitemap)))
        result.updated += 1
        # So the sitemap shows as pending straight away. A refresh that
        # fails doesn't undo the submission, so its errors are only noted.
        result.errors.concat(@refresh.call.errors) if @refresh
        result
      rescue ApiClient::Error => e
        result.errors << "Sitemap submission: #{e.message}"
        result
      end
    end
  end
end
