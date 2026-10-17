# encoding: UTF-8

module Google
  module Analytics
    # Apart from Users, as GA keeps new and returning readers under
    # Retention, so the breakdown is found where it would be in GA.
    class RetentionController < ApplicationController
      include DailyReport

      BREAKDOWNS = {
        "new-vs-returning" => DailyReport::Breakdown.new(key: "new-vs-returning", label: "New vs returning", keys: [:visitor_type],
          headings: ["Visitor type"], criteria: -> { VisitorTypeStat.all })
      }.freeze
      # The same traffic counts as Acquisition, so returning readers' figures
      # read against a source's.
      METRICS = AcquisitionController::METRICS
      LIVE_METRICS = AcquisitionController::LIVE_METRICS
      SHOW_SHARES = true
      CHART_METRIC = :views
      EVENT_FILTERING = true
      EXPORT_NAME = "analytics-retention"
      SYNC_SOURCE = "Google Analytics"
      SYNC_KIND = "analytics"
    end
  end
end
