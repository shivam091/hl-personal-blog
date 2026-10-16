# encoding: UTF-8

# Exists so the posts worth rewriting or retitling are picked out of Search
# Console's figures rather than hunted for.
class RankingReportsController < ApplicationController
  def show
    @period = Period.new(params)
    @opportunities = Google::SearchConsole::Opportunities.new(@period)

    respond_to do |format|
      format.html
      format.csv do
        exports = Google::SearchConsole::Opportunities::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        send_csv @opportunities.to_csv(export),
                 filename: "ranking-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
