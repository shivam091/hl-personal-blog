# encoding: UTF-8

module Google
  module Analytics
    # Asked of GA live rather than synced, since where a page's readers went
    # next is only known by following each of them on. Where they came from
    # is asked alongside, so the page is read from both sides. Cached, since
    # both are worked out again on each request.
    class PageFlowService
      CACHE_FOR = 1.hour
      LIMIT = 10
      # Enough referrers that, folded into pages and sites, the top ten are
      # still whole.
      REFERRER_ROWS = 100
      # GA's referrer for a view with none: typed, bookmarked or from an app.
      NO_REFERRER = "No referrer"

      # Kind is :page for the blog's own, :site for another, :none for no
      # referrer, so a page of the blog can be followed on from here.
      Source = Struct.new(:value, :kind, :views, keyword_init: true)
      # Every referrer GA gave, not just the top ones, so a period compared with
      # can say what each shown source had before even if it ranked lower then.
      Flow = Struct.new(:path, :views, :readers, :previous, :next_pages, :all_previous, keyword_init: true) do
        def all_previous
          self[:all_previous] || {}
        end
      end
      Result = Struct.new(:flow, :errors, keyword_init: true)

      class << self
        def call(...)
          new.call(...)
        end

        # Just a path the blog could serve, so a pasted link still works.
        def path(value)
          path = URI.parse(value.to_s.strip).path.presence
          path if path&.start_with?("/")
        rescue URI::InvalidURIError
          nil
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
        @hostname = options.fetch(:hostname) { Blog.host }
      end

      def call(period, path:)
        return Result.new(errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        return Result.new(errors: ["No Analytics property configured (credentials google.analytics_property_id)"]) if @property.blank?

        key = "google/analytics_page_flow/v2/#{@property}/#{Digest::MD5.hexdigest(path)}/#{period.from}/#{period.to}"
        Result.new(flow: @cache.fetch(key, expires_in: CACHE_FOR) { flow(period, path) }, errors: [])
      rescue ApiClient::Error => e
        Result.new(errors: ["Analytics page flow: #{e.message}"])
      end

      private

      def flow(period, path)
        report = fetch_previous(period, path)
        totals = Array(report.dig("totals", 0, "metricValues")).map { |value| value["value"].to_i }
        sources = folded_sources(report)
        Flow.new(path: path, views: totals.first.to_i, readers: totals.second.to_i, previous: sources.first(LIMIT),
          next_pages: next_pages(period, path), all_previous: sources.to_h { |source| [source.value, source.views] })
      end

      def fetch_previous(period, path)
        @client.post(format(SyncService::REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          dimensions: [{name: "pageReferrer"}],
          metrics: [{name: "screenPageViews"}, {name: "activeUsers"}],
          dimensionFilter: SyncService.dimension_filter([["pagePath", "EXACT", path]], @hostname),
          metricAggregations: ["TOTAL"],
          orderBys: [{metric: {metricName: "screenPageViews"}, desc: true}],
          limit: REFERRER_ROWS,
          returnPropertyQuota: true
        }).tap { |report| Quota.record("core", report) }
      end

      # The blog's own pages by path and other sites by host, since GA keeps
      # each full URL, query string and all, as a referrer of its own.
      def folded_sources(report)
        Array(report["rows"]).map { |row| [source(row.dig("dimensionValues", 0, "value")), row.dig("metricValues", 0, "value").to_i] }
          .group_by(&:first).map { |(value, kind), rows| Source.new(value: value, kind: kind, views: rows.sum(&:last)) }
          .sort_by { |source| [-source.views, source.value] }
      end

      def source(referrer)
        uri = URI.parse(referrer.to_s)
        return [NO_REFERRER, :none] if uri.host.blank?

        uri.host.casecmp?(@hostname) ? [uri.path.presence || "/", :page] : [uri.host.downcase.delete_prefix("www."), :site]
      rescue URI::InvalidURIError
        [referrer.to_s, :site]
      end

      # Followed as a one-step funnel, since only a funnel's next action
      # says what a reader did after a page, matched as a funnel step on the
      # page would be.
      def next_pages(period, path)
        step = FunnelStep.new(name: "Viewed #{path}", event: "page_view", path: path)
        report = @client.post(format(FunnelService::REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          funnel: {steps: [{name: step.name, filterExpression: FunnelService.filter_expression(step, @hostname)}]},
          funnelVisualizationType: "STANDARD_FUNNEL",
          funnelNextAction: {nextActionDimension: {name: FunnelService::NEXT_ACTIONS.dig("page", :dimension)}, limit: FunnelService::NEXT_LIMIT},
          returnPropertyQuota: true
        })
        Quota.record("funnel", report)
        FunnelService.next_actions_for(FunnelService.table_rows(report.fetch("funnelVisualization", {})), 0, limit: FunnelService::NEXT_LIMIT, page: true)
      end
    end
  end
end
