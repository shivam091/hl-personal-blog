# encoding: UTF-8

module Google
  module Analytics
    class RetentionController < ApplicationController
      include DailyReport
      include VisitorWeeks

      BREAKDOWNS = {
        "new-vs-returning" => DailyReport::Breakdown.new(key: "new-vs-returning", label: "New vs returning", keys: [:visitor_type],
          headings: ["Visitor type"], criteria: -> { Stat.all }),
        "new-vs-returning-pages" => DailyReport::Breakdown.new(key: "new-vs-returning-pages", label: "New vs returning + pages",
          keys: %i[visitor_type page_path], headings: ["Visitor type", "Page path"], criteria: -> { Stat.all },
          parent: "new-vs-returning", split_label: "By page")
      }.freeze
      # The same traffic counts as Acquisition, so returning readers' figures
      # read against a source's.
      METRICS = AcquisitionController::METRICS
      LIVE_METRICS = AcquisitionController::LIVE_METRICS
      SHOW_SHARES = true
      CHART_METRIC = :views
      EVENT_FILTERING = true
      EXPORT_NAME = "analytics-retention"
      LIST_LAYOUT = "analytics_retention"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"

      private

      def load_page
        super
        load_visitor_weeks
      end
    end
  end
end
