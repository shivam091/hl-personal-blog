# encoding: UTF-8

require "csv"

module Google
  module Analytics
    # Asked of GA live rather than synced, since a funnel counts each reader
    # once across the whole period and the days can't be added up. Cached,
    # since every step is worked out again on each request.
    class FunnelService
      # Only in v1alpha so far.
      REPORT_URL = "https://analyticsdata.googleapis.com/v1alpha/properties/%{property}:runFunnelReport"
      CACHE_FOR = 1.hour
      # GA's own dimensions, named as the Users report names its breakdowns.
      BREAKDOWNS = {
        "device" => {label: "Device", dimension: "deviceCategory"},
        "country" => {label: "Country", dimension: "countryId"}
      }.freeze
      # Enough countries to see where readers convert, few enough that the
      # table stays readable; GA folds the rest away.
      SEGMENT_LIMIT = 10
      # GA's name for a step's row over every segment.
      TOTAL = "RESERVED_TOTAL"

      Step = Struct.new(:name, :users, :completion_rate, :abandonments, :abandonment_rate, keyword_init: true)
      module Conversion
        # From the first step to the last, as GA's own funnel totals it.
        def conversion_rate
          first = steps.first&.users.to_i
          first.zero? ? nil : steps.last.users.fdiv(first)
        end
      end
      Segment = Struct.new(:value, :steps, keyword_init: true) { include Conversion }
      Funnel = Struct.new(:key, :title, :steps, :counted_since, :server_sent, :segments, keyword_init: true) do
        include Conversion

        def segments
          self[:segments] || []
        end
      end
      Result = Struct.new(:funnels, :breakdown, :errors, keyword_init: true)

      class << self
        def call(...)
          new.call(...)
        end

        # A row per step, the whole funnel's first and then each segment's,
        # so a spreadsheet can filter to either.
        def to_csv(funnels, previous: {})
          CSV.generate do |csv|
            csv << ["Funnel", "Segment", "Step number", "Step", "Readers", "Went on", "Dropped", "Readers before"]
            funnels.each do |funnel|
              before = previous[funnel.key]
              [[nil, funnel.steps, before&.steps], *funnel.segments.map do |segment|
                [segment.value, segment.steps, before&.segments&.find { |earlier| earlier.value == segment.value }&.steps]
              end].each do |value, steps, earlier|
                steps.each_with_index do |step, index|
                  last = index == steps.size - 1
                  csv << [funnel.title, value || "All", index + 1, step.name, step.users, (step.completion_rate&.round(4) unless last),
                    (step.abandonments unless last), earlier&.[](index)&.users]
                end
              end
            end
          end
        end
      end

      def initialize(options = {})
        @property = options.fetch(:property) { Rails.application.credentials.dig(:google, :analytics_property_id) }.to_s
        @client = options.fetch(:client) { ApiClient.new(scope: SyncService::SCOPE) }
        @cache = options.fetch(:cache, Rails.cache)
        @hostname = options.fetch(:hostname, SyncService::HOSTNAME)
      end

      # An unknown breakdown is read as none, so a mistyped link still shows
      # the funnels.
      def call(period, breakdown: nil, definitions: nil)
        breakdown = breakdown.presence_in(BREAKDOWNS.keys)
        return Result.new(funnels: [], breakdown: breakdown, errors: [ApiClient::NOT_CONFIGURED]) unless @client.configured?
        if @property.blank?
          return Result.new(
            funnels: [],
            breakdown: breakdown,
            errors: ["No Analytics property configured (credentials google.analytics_property_id)"]
          )
        end

        errors = []
        funnels = (definitions || FunnelDefinition.all_or_defaults).filter_map do |definition|
          key = "google/analytics_funnel/#{@property}/#{definition.cache_version}/#{breakdown}/#{period.from}/#{period.to}"
          @cache.fetch(key, expires_in: CACHE_FOR) { funnel(definition, fetch(definition, period, breakdown)) }
        # One refused funnel shouldn't cost the others.
        rescue ApiClient::Error => e
          errors << "Analytics funnel “#{definition.title}”: #{e.message}"
          nil
        end
        Result.new(funnels: funnels, breakdown: breakdown, errors: errors.uniq)
      end

      private

      def funnel(definition, report)
        rows = report_rows(report)
        segments = rows.keys.compact - [TOTAL]
        Funnel.new(
          key: definition.key,
          title: definition.title,
          counted_since: definition.counted_since,
          server_sent: definition.server_sent?,
          steps: steps(rows[TOTAL] || rows[nil] || [], definition),
          # Most readers first, as GA lists a breakdown.
          segments: segments.map { |value| Segment.new(value: value, steps: steps(rows[value], definition)) }
            .sort_by { |segment| [-segment.steps.first&.users.to_i, segment.value] }
        )
      end

      def fetch(definition, period, breakdown)
        body = {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          funnel: {steps: definition.steps.map { |step| {name: step.name, filterExpression: filter_expression(step)} }},
          returnPropertyQuota: true
        }
        if breakdown
          body[:funnelBreakdown] = {breakdownDimension: {name: BREAKDOWNS.fetch(breakdown)[:dimension]}, limit: SEGMENT_LIMIT}
        end
        @client.post(format(REPORT_URL, property: ERB::Util.url_encode(@property)), body).tap { |report| Quota.record("funnel", report) }
      end

      # Funnel steps refuse pagePath, so the path is matched with whatever
      # query string followed it.
      def filter_expression(step)
        expressions = [{funnelEventFilter: {eventName: step.event}}]
        expressions << field_filter("hostName", "EXACT", @hostname) if step.site
        if step.path.present?
          expressions << field_filter("pagePathPlusQueryString", "FULL_REGEXP", "#{Regexp.escape(step.path)}(\\?.*)?")
        end
        if step.paths.present?
          expressions << {
            orGroup: {expressions: step.paths.map { |prefix| field_filter("pagePathPlusQueryString", "BEGINS_WITH", prefix) }}
          }
        end
        expressions.one? ? expressions.first : {andGroup: {expressions: expressions}}
      end

      def field_filter(field, match_type, value)
        {funnelFieldFilter: {fieldName: field, stringFilter: {matchType: match_type, value: value, caseSensitive: false}}}
      end

      # Read by header name, since an alpha API may reorder its columns. GA
      # can list the headers twice over one row's values, and the empty
      # repeats would otherwise overwrite the real figures. Grouped by the
      # breakdown's value, nil when there's none.
      def report_rows(report)
        table = report.fetch("funnelTable", {})
        metrics = Array(table["metricHeaders"]).map { |header| header["name"] }
        Array(table["rows"]).map do |row|
          [
            row.dig("dimensionValues", 0, "value").to_s,
            row.dig("dimensionValues", 1, "value").presence,
            Array(row["metricValues"]).each_with_index.to_h do |value, index|
              [metrics[index], value["value"]]
            end
          ]
        end.group_by(&:second).transform_values { |rows| rows.map { |label, _, values| [label, values] } }
      end

      # GA numbers each step's name ("1. Visited the blog"), so rows are
      # matched by position instead; a step no one reached may have no row
      # at all.
      def steps(rows, definition)
        definition.steps.each_with_index.map do |step, index|
          values = rows.find { |label, _| label.start_with?("#{index + 1}.") }&.last || {}
          Step.new(
            name: step.name,
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
