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
        "browser" => {label: "Browser", dimension: "browser"},
        "operating-system" => {label: "Operating system", dimension: "operatingSystem"},
        "country" => {label: "Country", dimension: "countryId"},
        "language" => {label: "Language", dimension: "language"},
        "channel" => {label: "Channel", dimension: "sessionDefaultChannelGroup"},
        "source" => {label: "Source", dimension: "sessionSource"},
        "visitor-type" => {label: "New vs returning", dimension: "newVsReturning"}
      }.freeze
      # Enough countries or sources to see where readers convert, few enough that the
      # table stays readable; GA folds the rest away.
      SEGMENT_LIMIT = 10
      # GA refuses pagePath for a next action, so pages are asked with their
      # query strings and folded back into paths here.
      NEXT_ACTIONS = {
        "page" => {label: "Page", dimension: "pagePathPlusQueryString"},
        "event" => {label: "Event", dimension: "eventName"}
      }.freeze
      # GA's most for a next action, which is also enough to see where most
      # readers went.
      NEXT_LIMIT = 5
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
      # Trend is each day's readers at every step, by date; next actions are
      # each step's most common next page or event, as [value, readers].
      Funnel = Struct.new(:key, :title, :steps, :counted_since, :server_sent, :segments, :trend, :next_actions, keyword_init: true) do
        include Conversion

        def segments
          self[:segments] || []
        end

        def trend
          self[:trend] || {}
        end

        def next_actions
          self[:next_actions] || []
        end
      end
      Result = Struct.new(:funnels, :breakdown, :next_action, :errors, keyword_init: true)

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

        # Shared with Page flow, which follows readers on from one page as a
        # one-step funnel.
        def filter_expression(step, hostname)
          expressions = [{funnelEventFilter: {eventName: step.event}}]
          expressions << field_filter("hostName", "EXACT", hostname) if step.site
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

        # A step's next actions, most readers first. GA names the next
        # action's column its own way, so it's whichever isn't the step. A
        # page's query strings are folded into its path, which can count a
        # reader who reloaded it with another twice.
        def next_actions_for(rows, index, limit:, page:)
          rows.select { |row| row["funnelStepName"].to_s.start_with?("#{index + 1}.") }
            .filter_map do |row|
              value = row.except("funnelStepName", "activeUsers").values.first
              [page ? value.to_s.split("?").first : value, row["activeUsers"].to_i] if value.present?
            end
            .group_by(&:first).map { |value, counts| [value, counts.sum(&:last)] }
            .sort_by { |value, users| [-users, value] }.first(limit)
        end

        # Each row as one hash by header name, since an alpha API may reorder
        # its columns. GA can list the headers twice over one row's values,
        # so the first of a name wins over its empty repeat.
        def table_rows(table)
          read = ->(headers, values) { headers.map { |header| header["name"] }.zip(values.map { |value| value["value"] }).reverse.to_h }
          Array(table["rows"]).map do |row|
            read.(Array(table["dimensionHeaders"]), Array(row["dimensionValues"]))
              .merge(read.(Array(table["metricHeaders"]), Array(row["metricValues"])))
          end
        end

        private

        def field_filter(field, match_type, value)
          {funnelFieldFilter: {fieldName: field, stringFilter: {matchType: match_type, value: value, caseSensitive: false}}}
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
      # The trend comes with the funnel at no cost, but next actions are
      # asked of GA apart, since it won't trend them, so only when picked.
      def call(period, breakdown: nil, next_action: nil, definitions: nil)
        breakdown = breakdown.presence_in(BREAKDOWNS.keys)
        next_action = next_action.presence_in(NEXT_ACTIONS.keys)
        result = Result.new(funnels: [], breakdown: breakdown, next_action: next_action, errors: [])
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        if @property.blank?
          return result.tap { result.errors << "No Analytics property configured (credentials google.analytics_property_id)" }
        end

        # Versioned, so a funnel cached before trends were kept isn't read
        # back without one.
        result.funnels = (definitions || FunnelDefinition.all_or_defaults).filter_map do |definition|
          key = "google/analytics_funnel/v2/#{@property}/#{definition.cache_version}/#{breakdown}/#{next_action}/#{period.from}/#{period.to}"
          @cache.fetch(key, expires_in: CACHE_FOR) do
            funnel(definition, fetch(definition, period, breakdown), (fetch_next(definition, period, next_action) if next_action), next_action)
          end
        # One refused funnel shouldn't cost the others.
        rescue ApiClient::Error => e
          result.errors << "Analytics funnel “#{definition.title}”: #{e.message}"
          nil
        end
        result.tap { result.errors.uniq! }
      end

      private

      def funnel(definition, report, next_report, next_action)
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
            .sort_by { |segment| [-segment.steps.first&.users.to_i, segment.value] },
          trend: trend(report, definition),
          next_actions: (next_actions(next_report, definition, next_action) if next_report)
        )
      end

      def fetch(definition, period, breakdown)
        body = request(definition, period).merge(funnelVisualizationType: "TRENDED_FUNNEL")
        if breakdown
          body[:funnelBreakdown] = {breakdownDimension: {name: BREAKDOWNS.fetch(breakdown)[:dimension]}, limit: SEGMENT_LIMIT}
        end
        post(body)
      end

      def fetch_next(definition, period, next_action)
        post(request(definition, period).merge(
          funnelVisualizationType: "STANDARD_FUNNEL",
          funnelNextAction: {nextActionDimension: {name: NEXT_ACTIONS.fetch(next_action)[:dimension]}, limit: NEXT_LIMIT}
        ))
      end

      def request(definition, period)
        {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          funnel: {steps: definition.steps.map { |step| {name: step.name, filterExpression: self.class.filter_expression(step, @hostname)} }},
          returnPropertyQuota: true
        }
      end

      def post(body)
        @client.post(format(REPORT_URL, property: ERB::Util.url_encode(@property)), body).tap { |report| Quota.record("funnel", report) }
      end

      # Readers at each step on each day, from the trended view. A split adds
      # its own column there too, so only its total rows are read, or every
      # row summed where GA gives none.
      def trend(report, definition)
        rows = self.class.table_rows(report.fetch("funnelVisualization", {})).select { |row| row["date"] }
        split = rows.flat_map(&:keys).uniq - %w[date funnelStepName activeUsers]
        totals = rows.select { |row| split.any? { |name| row[name] == TOTAL } }
        rows = totals if totals.any?
        rows.group_by { |row| Date.strptime(row["date"], "%Y%m%d") }.sort.to_h.transform_values do |day|
          definition.steps.each_index.map do |index|
            day.select { |row| row["funnelStepName"].to_s.start_with?("#{index + 1}.") }.sum { |row| row["activeUsers"].to_i }
          end
        end
      end

      def next_actions(report, definition, next_action)
        rows = self.class.table_rows(report.fetch("funnelVisualization", {}))
        definition.steps.each_index.map do |index|
          self.class.next_actions_for(rows, index, limit: NEXT_LIMIT, page: next_action == "page")
        end
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
