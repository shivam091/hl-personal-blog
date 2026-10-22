# encoding: UTF-8

# Exists so a sync that keeps failing or slowing down is seen as a trend,
# not only as rows in the sync requests list.
class SyncReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @syncs = SyncStats.new(@period)
  end
end
