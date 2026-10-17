# encoding: UTF-8

class RankingOpportunityReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @opportunities = Google::SearchConsole::Opportunities.new(@period, summary: Google::SearchConsole::Summary.new(@period, country: @stats.country))
    @ai_gaps = Google::SearchConsole::AiGaps.new(Google::SearchConsole::GenerativeAiSummary.new(@period))

    respond_to do |format|
      format.html
      format.csv do
        exports = Google::SearchConsole::Opportunities::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        send_csv @opportunities.to_csv(export),
                 filename: "ranking-opportunities-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
