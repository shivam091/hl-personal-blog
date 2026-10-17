# encoding: UTF-8

module Google
  module Analytics
    # Asked of GA live rather than synced, since a funnel counts each reader
    # once across the whole period and the days can't be added up. Cached,
    # since every step is worked out again on each request.
    class FunnelService
      # Only in v1alpha so far.
      REPORT_URL = "https://analyticsdata.googleapis.com/v1alpha/properties/%{property}:runFunnelReport"
      CACHE_FOR = 1.hour
      # Where the blog's entries live, so a step on an entry isn't any page.
      ENTRY_PREFIXES = %w[/post/ /tutorial/ /snippet/].freeze

      Step = Struct.new(:name, :users, :completion_rate, :abandonments, :abandonment_rate, keyword_init: true)
      Funnel = Struct.new(:key, :title, :steps, keyword_init: true) do
        # From the first step to the last, as GA's own funnel totals it.
        def conversion_rate
          first = steps.first&.users.to_i
          first.zero? ? nil : steps.last.users.fdiv(first)
        end
      end
      Result = Struct.new(:funnels, :errors, keyword_init: true)

      # Subscribing and getting in touch are sent from the blog's server,
      # which GA files without a hostname, so only the steps before them are
      # kept to the live site. A reader can download the resume from the
      # footer of any page, so no page stands between visiting and it.
      FUNNELS = {
        "newsletter" => {
          title: "Reading to subscribing",
          steps: [
            ["Visited the blog", {event: "session_start", site: true}],
            ["Read an entry", {event: "page_view", paths: ENTRY_PREFIXES, site: true}],
            ["Subscribed to the newsletter", {event: "newsletter_subscribe"}]
          ]
        },
        "contact" => {
          title: "Visiting to getting in touch",
          steps: [
            ["Visited the blog", {event: "session_start", site: true}],
            ["Opened the contact page", {event: "page_view", path: "/contact", site: true}],
            ["Sent a message", {event: "contact_submit"}]
          ]
        },
        "share" => {
          title: "Reading to sharing",
          # The share bar sent nothing to GA before this.
          counted_since: Date.new(2026, 10, 23),
          steps: [
            ["Visited the blog", {event: "session_start", site: true}],
            ["Read an entry", {event: "page_view", paths: ENTRY_PREFIXES, site: true}],
            ["Shared the entry", {event: "share", paths: ENTRY_PREFIXES, site: true}]
          ]
        },
        "resume" => {
          title: "Visiting to downloading the resume",
          steps: [
            ["Visited the blog", {event: "session_start", site: true}],
            ["Downloaded the resume", {event: "download_resume", site: true}]
          ]
        }
      }.freeze

      class << self
        def call(...)
          new.call(...)
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
        @hostname = options.fetch(:hostname, SyncService::HOSTNAME)
      end

      def call(period)
        return Result.new(funnels: [], errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        if @property.blank?
          return Result.new(
            funnels: [],
            errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
          )
        end

        errors = []
        funnels = FUNNELS.filter_map do |key, funnel|
          @cache.fetch("google/analytics_funnel/#{@property}/#{key}/#{period.from}/#{period.to}", expires_in: CACHE_FOR) do
            Funnel.new(key: key, title: funnel[:title], steps: steps(fetch(funnel, period), funnel))
          end
        # One refused funnel shouldn't cost the others.
        rescue ApiClient::Error => e
          errors << "Analytics funnel “#{funnel[:title]}”: #{e.message}"
          nil
        end
        Result.new(funnels: funnels, errors: errors.uniq)
      end

      private

      def fetch(funnel, period)
        @client.post(format(REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          funnel: {steps: funnel[:steps].map { |name, step| {name: name, filterExpression: filter_expression(step)} }},
          returnPropertyQuota: true
        }).tap { |report| Quota.record("funnel", report) }
      end

      # Funnel steps refuse pagePath, so the path is matched with whatever
      # query string followed it.
      def filter_expression(step)
        expressions = [{funnelEventFilter: {eventName: step[:event]}}]
        expressions << field_filter("hostName", "EXACT", @hostname) if step[:site]
        if step[:path]
          expressions << field_filter("pagePathPlusQueryString", "FULL_REGEXP", "#{Regexp.escape(step[:path])}(\\?.*)?")
        end
        if step[:paths]
          expressions << {
            orGroup: {expressions: step[:paths].map { |prefix| field_filter("pagePathPlusQueryString", "BEGINS_WITH", prefix) }}
          }
        end
        expressions.one? ? expressions.first : {andGroup: {expressions: expressions}}
      end

      def field_filter(field, match_type, value)
        {funnelFieldFilter: {fieldName: field, stringFilter: {matchType: match_type, value: value, caseSensitive: false}}}
      end

      # Read by header name, since an alpha API may reorder its columns. GA
      # numbers each step's name ("1. Visited the blog"), so rows are matched
      # by position instead; a step no one reached may have no row at all.
      # GA can list the headers twice over one row's values, and the empty
      # repeats would otherwise overwrite the real figures.
      def steps(report, funnel)
        table = report.fetch("funnelTable", {})
        metrics = Array(table["metricHeaders"]).map { |header| header["name"] }
        rows = Array(table["rows"]).map do |row|
          [
            row.dig("dimensionValues", 0, "value").to_s,
            Array(row["metricValues"]).each_with_index.to_h do |value, index|
              [metrics[index], value["value"]]
            end
          ]
        end
        funnel[:steps].each_with_index.map do |(name, _), index|
          values = rows.find { |label, _| label.start_with?("#{index + 1}.") }&.last || {}
          Step.new(
            name: name,
            users: values["activeUsers"].to_i,
            completion_rate: values["funnelStepCompletionRate"]&.to_f,
            abandonments: values["funnelStepAbandonments"].to_i,
            abandonment_rate: values["funnelStepAbandonmentRate"]&.to_f
          )
        end
      end
    end
  end
end
