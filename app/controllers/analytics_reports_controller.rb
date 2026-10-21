# encoding: UTF-8

# Exists so the few Analytics rows that need acting on aren't lost among
# every row.
class AnalyticsReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @insights = Google::Analytics::Insights.new(@period, country: @stats.country)

    respond_to do |format|
      format.html
      format.csv do
        exports = Google::Analytics::Insights::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        send_csv @insights.to_csv(export),
                 filename: "analytics-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
