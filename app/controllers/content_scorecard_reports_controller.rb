# encoding: UTF-8

class ContentScorecardReportsController < ApplicationController
  include BlogStatsFilters

  # Shaped like the other list states, so changing the period or country
  # keeps the chosen order.
  Sort = Struct.new(:key) do
    def query
      key == ContentScorecard::SORTS.keys.first ? {} : {sort: key}
    end
  end

  def show
    load_blog_stats
    @content = ContentStats.new(@stats, search: Google::SearchConsole::Summary.new(@period))
    @sort = Sort.new(params[:sort].presence_in(ContentScorecard::SORTS.keys) || ContentScorecard::SORTS.keys.first)
    @ai = Google::SearchConsole::GenerativeAiSummary.new(@period)
    @scorecard = ContentScorecard.new(@content, ai: @ai)
    @rows = @scorecard.rows(sort: @sort.key)
    @consent = ConsentKpis.new(@period)

    respond_to do |format|
      format.html
      format.csv do
        send_csv @scorecard.to_csv(sort: @sort.key),
                 filename: "content-scorecard-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{ContentScorecard::SORTS[@sort.key]}, #{@period}"
      end
    end
  end
end
