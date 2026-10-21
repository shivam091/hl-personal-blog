# encoding: UTF-8

# Exists so it's known how far the figures can be trusted before acting on
# them.
class DataQualityReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @analytics = Google::Analytics::Summary.new(@period, country: @stats.country)
    @search = Google::SearchConsole::Summary.new(@period)
    comparison = ViewComparison.new(@stats, @analytics)
    @rows = comparison.rows

    respond_to do |format|
      format.html do
        @lifetime_hits = PageView.hit_totals
        @syncs = SyncRequest.freshness
        @coverage = IndexCoverage.new
      end
      format.csv do
        send_csv comparison.to_csv,
                 filename: "views-blog-vs-ga-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Blog vs GA views, #{@period}"
      end
    end
  end
end
