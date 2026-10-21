# encoding: UTF-8

# Exists so the contact form's spam protection can be judged on the
# messages it let through, and so none of them wait unanswered.
class MessageReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    # Left to the period's length until a bucket is picked.
    by = ChartGranularity.new(params, period: @period).by if params[:by].present?
    @messages = MessageStats.new(@period, country: @stats.country, by: by)
    @granularity = ChartGranularity.new({by: @messages.per.to_s})

    respond_to do |format|
      format.html
      format.csv do
        send_csv @messages.to_csv,
                 filename: "messages-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "Messages, #{@period}"
      end
    end
  end
end
