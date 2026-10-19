# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from the Chrome UX Report's history because that only
    # exists once enough Chrome users visit for Google to report, whereas
    # these cover every reader in any browser that measures them.
    class WebVitalsController < ApplicationController
      include DailyReport

      # Fewer reports than this, and one slow visit makes a page look slow.
      MIN_REPORTS = 10
      # GA only sums an event's value, so its mean is all that can be read
      # back, not the 75th percentile Google rates by; the bands are applied
      # to it as a guide.
      MEAN_HINT = "The average of the values readers' browsers reported. Google rates a page by its 75th percentile, which GA can't give, " \
        "so a mean in the good band can still hide a slow quarter of visits."

      class << self
        def metrics_for(metric)
          [
            DailyReport::Metric.new(field: :event_count, label: "Reports", format: :count, icon: "activity",
              hint: "The number of times readers' browsers reported this metric."),
            DailyReport::Metric.new(field: :good_share, label: "Good", format: :percent, icon: "check-circle", color: "#0b7d60",
              hint: "The share of rated reports in Google's good band."),
            DailyReport::Metric.new(field: :needs_improvement_share, label: "Needs improvement", format: :percent, icon: "alert-triangle",
              lower_is_better: true, hint: "The share of rated reports between Google's good and poor bands."),
            DailyReport::Metric.new(field: :poor_share, label: "Poor", format: :percent, icon: "alert-circle", lower_is_better: true, color: "#c2410c",
              hint: "The share of rated reports in Google's poor band."),
            DailyReport::Metric.new(field: :mean_value, label: "Mean", format: metric == "CLS" ? :score : :milliseconds, icon: "timer",
              lower_is_better: true, color: "#1f6fd1", hint: MEAN_HINT)
          ]
        end
      end

      BREAKDOWNS = WebVitalStat::METRICS.to_h do |metric|
        key = metric.downcase
        [key, DailyReport::Breakdown.new(key: key, label: metric, keys: [:page_path], headings: ["Page path"],
          criteria: -> { WebVitalStat.where(metric: metric) }, metrics: metrics_for(metric))]
      end.freeze
      METRICS = metrics_for("LCP").freeze
      CHART_METRIC = :mean_value
      EXPORT_NAME = "analytics-web-vitals"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"

      private

      def load_page
        super
        criteria = @filtering.apply(@period.apply(WebVitalStat.all))
        @overview = WebVitalStat.overview(criteria)
        @slowest = WebVitalStat::METRICS.index_with { |metric| WebVitalStat.slowest_pages(criteria, metric, min_reports: MIN_REPORTS, limit: 3) }
        return unless @previous_totals

        # Only when the earlier period was synced, as for the report's own
        # figures, so a first period doesn't read as a jump from nothing.
        before = @filtering.apply(@period.previous.apply(WebVitalStat.all))
        @previous_overview = WebVitalStat.overview(before)
        @previous_slowest = WebVitalStat::METRICS.index_with do |metric|
          pages = @slowest.fetch(metric).map { |page| page[:page_path] }
          pages.empty? ? {} : WebVitalStat.grouped(before.where(metric: metric, :page_path.in => pages), by: [:page_path]).to_h { |row| [row[:page_path], row.mean_value] }
        end
      end
    end
  end
end
