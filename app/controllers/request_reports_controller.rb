# encoding: UTF-8

# Exists so errors and slow pages show up as a trend, not only as rows in
# the request log.
class RequestReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @requests = RequestStats.new(@period)
  end
end
