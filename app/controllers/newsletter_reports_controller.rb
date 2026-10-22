# encoding: UTF-8

# Exists so it's known whether entries grow the list and whether the mail
# announcing them gets through.
class NewsletterReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @newsletter = NewsletterStats.new(@period, country: @stats.country)
    @audience = NewsletterAudience.new(@period)
    @engagement = NewsletterEngagement.new(@period)

    respond_to do |format|
      format.html
      format.csv do
        exports = NewsletterStats::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        send_csv @newsletter.to_csv(export),
                 filename: "newsletter-#{export}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
