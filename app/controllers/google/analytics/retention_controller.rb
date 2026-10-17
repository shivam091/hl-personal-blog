# encoding: UTF-8

module Google
  module Analytics
    # Apart from Users, as GA keeps new and returning readers under
    # Retention, so the breakdown is found where it would be in GA.
    class RetentionController < ApplicationController
      include DailyReport

      BREAKDOWNS = {
        "new-vs-returning" => DailyReport::Breakdown.new(key: "new-vs-returning", label: "New vs returning", keys: [:visitor_type],
          headings: ["Visitor type"], criteria: -> { VisitorTypeStat.all }),
        # Which posts bring readers back, which the unsplit tab can't say.
        "new-vs-returning-pages" => DailyReport::Breakdown.new(key: "new-vs-returning-pages", label: "New vs returning + pages",
          keys: %i[visitor_type page_path], headings: ["Visitor type", "Page path"], criteria: -> { VisitorTypeStat.all },
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
    end
  end
end
