# encoding: UTF-8

# Exists so a service that's refusing or slowing down is seen as a trend,
# not only as failed rows in the external calls list.
class ExternalCallReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @calls = ExternalCallStats.new(@period)
  end
end
