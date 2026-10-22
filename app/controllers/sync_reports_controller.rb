# encoding: UTF-8

# Exists so a sync that keeps failing or slowing down is seen as a trend,
# not only as rows in the sync requests list.
class SyncReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @syncs = SyncStats.new(@period)

    respond_to do |format|
      format.html
      format.csv do
        send_csv @syncs.to_csv,
                 filename: "sync-health-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Syncs by kind, #{@period}"
      end
    end
  end
end
