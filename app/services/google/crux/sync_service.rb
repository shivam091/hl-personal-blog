# encoding: UTF-8

module Google
  module Crux
    # The whole site rather than each page, since CrUX only reports a page
    # with plenty of Chrome readers, and a small blog's origin is far more
    # likely to have enough. Every window Google still holds is fetched each
    # run, as it may revise the latest.
    class SyncService
      HISTORY_URL = "https://chromeuxreport.googleapis.com/v1/records:queryHistoryRecord"
      # The most Google returns.
      PERIODS = 40

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(client: KeyClient.new, origin: "https://#{Analytics::SyncService::HOSTNAME}")
        @client = client
        @origin = origin
      end

      def call
        result = SyncResult.empty
        return result.tap { result.errors << KeyClient::NOT_CONFIGURED } unless @client.configured?

        synced = SyncLock.hold("google/crux") do
          missing = Stat::FORM_FACTORS.keys.reject do |form_factor|
            Stat.sync(rows(form_factor), result)
            true
          # Too few Chrome readers on one device is expected for a small
          # blog, so it only counts as a failure when no device has any.
          rescue KeyClient::Error => e
            raise unless e.status == 404

            false
          end
          if missing.size == Stat::FORM_FACTORS.size
            result.errors << "CrUX has too few Chrome users of #{@origin} to report on"
          end
        rescue KeyClient::Error => e
          result.errors << "CrUX: #{e.message}"
        end
        result.errors << "CrUX: another sync is already running, so this one was skipped" unless synced
        result
      end

      private

      def rows(form_factor)
        record = @client.post(HISTORY_URL, {
          origin: @origin,
          formFactor: (form_factor unless form_factor == "ALL"),
          metrics: Stat::METRICS.values,
          collectionPeriodCount: PERIODS
        }.compact).fetch("record", {})
        metrics = record.fetch("metrics", {})

        Array(record["collectionPeriods"]).each_with_index.map do |window, index|
          values = Stat::METRICS.to_h do |short, name|
            metric = metrics.fetch(name, {})
            [
              short,
              [
                number(metric.dig("percentilesTimeseries", "p75s", index)),
                number(metric.dig("histogramTimeseries", 0, "densities", index))
              ]
            ]
          end

          {
            date: date(window["lastDate"]), form_factor: form_factor, first_date: date(window["firstDate"]),
            p75: values.transform_values(&:first).compact, good: values.transform_values(&:last).compact
          }
        end
      end

      def date(parts)
        Date.new(parts["year"], parts["month"], parts["day"])
      end

      # CLS comes as a string ("0.05"), a window with too few readers as
      # null or "NaN".
      def number(value)
        Float(value) if value.present? && value.to_s != "NaN"
      rescue ArgumentError, TypeError
        nil
      end
    end
  end
end
