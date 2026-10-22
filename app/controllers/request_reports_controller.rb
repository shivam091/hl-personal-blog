# encoding: UTF-8

# Exists so errors and slow pages show up as a trend, not only as rows in
# the request log.
class RequestReportsController < ApplicationController
  def show
    @period = Period.new(params)
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
