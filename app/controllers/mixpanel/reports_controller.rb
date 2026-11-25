# encoding: UTF-8

module Mixpanel
  class ReportsController < ApplicationController
    def show
      @period = Period.new(params)
      @report = Report.new(@period)
      @granularity = ChartGranularity.new(params, period: @period)

      respond_to do |format|
        format.html
        format.csv do
          send_csv @report.to_csv,
                   filename: "mixpanel-pages-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                   detail: "Mixpanel pages, #{@period}"
        end
      end
    end

    # The days on screen, so what's being looked at is what gets refreshed.
    def sync
      period = Period.new(params)
      days = [(Date.current - period.from).to_i + 1, SyncService::MAX_DAYS].min
      SyncRequest.enqueue("mixpanel", **SyncRequest.range(days))
      redirect_to mixpanel_report_path(period.query),
                  notice: "Syncing Mixpanel for the last #{days} days in the background. Refresh in a moment to see the figures."
    end
  end
end
