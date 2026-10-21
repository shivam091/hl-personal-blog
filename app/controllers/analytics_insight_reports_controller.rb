# encoding: UTF-8

# Exists so the few Analytics rows that need acting on aren't lost among
# every row.
class AnalyticsInsightReportsController < ApplicationController
  include BlogStatsFilters

  TRENDS = %w[views engagement_rate read_through key_events].freeze

  def show
    load_blog_stats
    @insights = Google::Analytics::Insights.new(@period, country: @stats.country)
    @granularity = ChartGranularity.new(params)
    @trend = params[:trend].presence_in(TRENDS) || TRENDS.first
    @published = FeedEntry.published_names(@period)

    respond_to do |format|
      format.html
      format.csv do
        exports = Google::Analytics::Insights::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        send_csv @insights.to_csv(export),
                 filename: "analytics-insights-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
