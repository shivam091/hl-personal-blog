# encoding: UTF-8

module Google
  module Analytics
    # Exists because users and sessions can't be added up from stored daily
    # rows: GA counts a reader once over a whole period, however many days
    # and pages they touched. Cached since a report is reloaded as it's
    # sorted and paged.
    class LiveFigures
      include Connected

      CACHE_FOR = 1.hour

      Result = Struct.new(:rows, :total, keyword_init: true)

      # One error whatever went wrong, since all a reader needs is why the
      # user and session figures fell back to the stored ones.
      class Unavailable < StandardError; end

      class << self
        def call(...)
          new.call(...)
        end
      end

      def initialize(options = {})
        connect(options)
      end

      def call(from:, to:, dimensions:, metrics:, filters: [])
        raise Unavailable, "the Google service account isn't configured" unless @client.configured?
        raise Unavailable, "no Analytics property is configured" if @property.blank?

        key = [@property, @hostname, from, to, dimensions.to_a, metrics.to_a, filters].to_json
        @cache.fetch("google/analytics/live/#{Digest::SHA256.hexdigest(key)}", expires_in: CACHE_FOR) do
          range = {startDate: from.iso8601, endDate: to.iso8601}
          filter = dimension_filter(filters)
          rows = fetch_all(range, dimensions.values, metrics.values, filter).to_h do |row|
            values = dimensions.keys.zip(row["dimensionValues"]).map { |field, value| SyncService.normalize(field, value["value"]) }
            [values, counts(metrics, row)]
          end
          # Asked apart, since GA's total counts each reader once, which no
          # sum of its rows does.
          total = fetch_all(range, [], metrics.values, filter).first
          Result.new(rows: rows, total: total ? counts(metrics, total) : metrics.keys.index_with(0))
        end
      rescue ApiClient::Error => e
        raise Unavailable, e.message
      end

      private

      def counts(metrics, row)
        metrics.keys.zip(row["metricValues"]).to_h { |field, value| [field, value["value"].to_i] }
      end

      def dimension_filter(filters)
        SyncService.dimension_filter(filters, @hostname)
      end

      def fetch_all(range, dimensions, metrics, filter)
        url = format(SyncService::REPORT_URL, property: ERB::Util.url_encode(@property))
        rows = []
        loop do
          report = @client.post(url, {
            dateRanges: [range], dimensions: dimensions.map { |name| {name: name} }, metrics: metrics.map { |name| {name: name} },
            dimensionFilter: filter, limit: SyncService::ROW_LIMIT, offset: rows.size,
            returnPropertyQuota: true
          })
          Quota.record("core", report)
          rows.concat(report.fetch("rows", []))
          return rows if rows.size >= report["rowCount"].to_i || report.fetch("rows", []).empty?
        end
      end
    end
  end
end
