# encoding: UTF-8

class SearchInsightReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @granularity = ChartGranularity.new(params, period: @period)
    load_google_summaries
    @query_groups = Google::SearchConsole::QueryGroups.new(@period, country: @stats.country)
    # Another country's are read over the same dates, as the totals are.
    if @search.compared?
      @previous_query_groups = Google::SearchConsole::QueryGroups.new(@period.previous, country: @period.previous.country || @stats.country)
    end

    respond_to do |format|
      format.html
      format.csv do
        exports = Google::SearchConsole::Summary::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        send_csv @search.to_csv(export, blog_stats: @stats),
                 filename: "search-insights-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
