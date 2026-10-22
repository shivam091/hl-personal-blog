# encoding: UTF-8

# Exists so a service that's refusing or slowing down is seen as a trend,
# not only as failed rows in the external calls list.
class ApiHealthReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @calls = ExternalCallStats.new(@period)

    respond_to do |format|
      format.html
      format.csv do
        send_csv @calls.to_csv,
                 filename: "api-health-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Calls by service, #{@period}"
      end
    end
  end
end
