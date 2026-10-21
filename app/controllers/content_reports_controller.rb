# encoding: UTF-8

# Exists so writing effort goes to the kinds of content that pay.
class ContentReportsController < ApplicationController
  include BlogStatsFilters

  def show
    load_blog_stats
    @search = Google::SearchConsole::Summary.new(@period)
    @content = ContentStats.new(@stats, search: @search)

    respond_to do |format|
      format.html
      format.csv do
        exports = ContentStats::EXPORTS
        export = params[:export].presence_in(exports.keys) || exports.keys.first
        name = export == exports.keys.first ? "content" : "content-#{export}"

        send_csv @content.to_csv(export),
                 filename: "#{name}-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{exports[export]}, #{@period}"
      end
    end
  end
end
