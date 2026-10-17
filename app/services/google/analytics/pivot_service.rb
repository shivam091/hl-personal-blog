# encoding: UTF-8

require "csv"

module Google
  module Analytics
    # Asked of GA live rather than synced, since a reader counts once in a
    # cell and once in its row's and column's totals, which stored daily rows
    # can't give. Cached, since the grid is asked again as picks change.
    class PivotService
      include Connected

      REPORT_URL = "https://analyticsdata.googleapis.com/v1beta/properties/%{property}:runPivotReport"
      CACHE_FOR = 1.hour
      # Reuses the funnels' splits so the same breakdown means the same dimension
      # in both.
      DIMENSIONS = FunnelService::BREAKDOWNS.merge("page" => {label: "Page", dimension: "pagePath"}).freeze
      METRICS = {
        "readers" => {label: "Readers", metric: "activeUsers"},
        "sessions" => {label: "Sessions", metric: "sessions"},
        "views" => {label: "Views", metric: "screenPageViews"},
        "key-events" => {label: "Key events", metric: "keyEvents"}
      }.freeze
      DEFAULT_ROWS = "channel"
      DEFAULT_COLUMNS = "device"
      DEFAULT_METRIC = "readers"
      # Enough rows to cover most readers, few enough columns to fit a card.
      ROW_LIMIT = 15
      COLUMN_LIMIT = 8
      # GA's name for a row's or column's total.
      TOTAL = "RESERVED_TOTAL"

      Table = Struct.new(:rows, :columns, :cells, :row_totals, :column_totals, :total, keyword_init: true) do
        def [](row, column)
          cells[[row, column]]
        end

        def empty?
          rows.empty?
        end
      end
      Result = Struct.new(:table, :rows, :columns, :metric, :errors, keyword_init: true)

      class << self
        def call(...)
          new.call(...)
        end

        def to_csv(result, previous = nil)
          table = result.table
          earlier = previous&.table
          cell = ->(value, before) { CompareChange.cell(value, before.to_i, compare: !earlier.nil?) }
          CSV.generate do |csv|
            csv << [DIMENSIONS.dig(result.rows, :label), *table.columns, "Total"]
            table.rows.each do |row|
              csv << [row, *table.columns.map { |column| cell.(table[row, column], earlier&.[](row, column)) }, cell.(table.row_totals[row], earlier&.row_totals&.[](row))]
            end
            csv << ["Total", *table.columns.map { |column| cell.(table.column_totals[column], earlier&.column_totals&.[](column)) }, cell.(table.total, earlier&.total)]
          end
        end
      end

      def initialize(options = {})
        connect(options)
      end

      # A pick not offered is read as the default, and columns the same as
      # rows as the default columns, so a mistyped link still shows a grid.
      def call(period, rows: nil, columns: nil, metric: nil)
        rows = rows.presence_in(DIMENSIONS.keys) || DEFAULT_ROWS
        columns = columns.presence_in(DIMENSIONS.keys - [rows]) || ([DEFAULT_COLUMNS, DEFAULT_ROWS] - [rows]).first
        metric = metric.presence_in(METRICS.keys) || DEFAULT_METRIC
        result = Result.new(table: Table.new(rows: [], columns: [], cells: {}, row_totals: {}, column_totals: {}), rows: rows, columns: columns,
          metric: metric, errors: [])
        return result.tap { result.errors << ApiClient::NOT_CONFIGURED } unless @client.configured?
        if @property.blank?
          return result.tap { result.errors << "No Analytics property configured (credentials google.analytics_property_id)" }
        end

        key = "google/analytics_pivot/#{@property}/#{rows}/#{columns}/#{metric}/#{period.from}/#{period.to}"
        result.tap { result.table = @cache.fetch(key, expires_in: CACHE_FOR) { table(fetch(period, rows, columns, metric), rows, columns) } }
      rescue ApiClient::Error => e
        result.tap { result.errors << "Analytics cross-tab: #{e.message}" }
      end

      private

      def fetch(period, rows, columns, metric)
        metric = METRICS.fetch(metric)[:metric]
        pivot = ->(key, limit) do
          {fieldNames: [DIMENSIONS.fetch(key)[:dimension]], limit: limit, metricAggregations: ["TOTAL"],
           orderBys: [{metric: {metricName: metric}, desc: true}]}
        end
        @client.post(format(REPORT_URL, property: ERB::Util.url_encode(@property)), {
          dateRanges: [{startDate: period.from.iso8601, endDate: period.to.iso8601}],
          # A pivot report only filters on a dimension it returns, so the
          # hostname is a pivot of its own, one value wide.
          dimensions: [*[rows, columns].map { |key| {name: DIMENSIONS.fetch(key)[:dimension]} }, {name: "hostName"}],
          metrics: [{name: metric}],
          dimensionFilter: SyncService.dimension_filter([], @hostname),
          pivots: [pivot.(rows, ROW_LIMIT), pivot.(columns, COLUMN_LIMIT), {fieldNames: ["hostName"], limit: 1}],
          returnPropertyQuota: true
        }).tap { |report| Quota.record("core", report) }
      end

      # Rows and columns in GA's order, most first; the totals are GA's own,
      # each reader counted once however many cells they're in.
      def table(report, rows, columns)
        names = Array(report["dimensionHeaders"]).map { |header| header["name"] }
        row_index = names.index(DIMENSIONS.fetch(rows)[:dimension]) || 0
        column_index = names.index(DIMENSIONS.fetch(columns)[:dimension]) || 1
        values = [*Array(report["rows"]), *Array(report["aggregates"])].to_h do |row|
          dimensions = Array(row["dimensionValues"]).map { |value| value["value"].to_s }
          [[dimensions[row_index], dimensions[column_index]], row.dig("metricValues", 0, "value").to_f.round]
        end
        headers = ->(index) do
          Array(report.dig("pivotHeaders", index, "pivotDimensionHeaders")).map { |header| header.dig("dimensionValues", 0, "value").to_s } - [TOTAL]
        end
        row_values = headers.(0)
        column_values = headers.(1)
        Table.new(
          rows: row_values,
          columns: column_values,
          cells: values.reject { |(row, column), _| row == TOTAL || column == TOTAL },
          row_totals: row_values.index_with { |row| values[[row, TOTAL]] },
          column_totals: column_values.index_with { |column| values[[TOTAL, column]] },
          total: values[[TOTAL, TOTAL]]
        )
      end
    end
  end
end
