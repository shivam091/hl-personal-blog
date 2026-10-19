# encoding: UTF-8

module Google
  module Analytics
    # Apart from the Chrome UX Report's history, which stays for when the
    # blog has enough Chrome users for Google to report on: these are every
    # reader's, in any browser that measures them, as the blog sends them
    # to GA.
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
      # The slowest pages charted, so where readers wait longest stands out.
      CHART_METRIC = :mean_value
      EXPORT_NAME = "analytics-web-vitals"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"

      private

      # Every metric at once over the same pages and days, so a tab is
      # picked knowing which metric is the one to look into.
      def load_page
        super
        criteria = @filtering.apply(@period.apply(WebVitalStat.all))
        @overview = WebVitalStat.overview(criteria)
        @slowest = WebVitalStat::METRICS.index_with { |metric| WebVitalStat.slowest_pages(criteria, metric, min_reports: MIN_REPORTS, limit: 3) }
      end
    end
  end
end
