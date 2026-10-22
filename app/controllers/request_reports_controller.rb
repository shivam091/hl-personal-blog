# encoding: UTF-8

class RequestReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @granularity = ChartGranularity.new(params, period: @period)
    @requests = RequestStats.new(@period)

    respond_to do |format|
      format.html
      format.csv do
        send_csv @requests.to_csv,
                 filename: "requests-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Requests by page, #{@period}"
      end
    end
  end
end
