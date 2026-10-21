# encoding: UTF-8

# Exists so Search Console's figures become things to act on rather than
# rows to read through.
class SearchInsightReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    load_google_summaries
    @query_groups = Google::SearchConsole::QueryGroups.new(@period, country: @stats.country)

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
