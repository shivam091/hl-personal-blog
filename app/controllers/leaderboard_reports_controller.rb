# encoding: UTF-8

# Exists so entries can be judged on every measure at once rather than by
# whichever list they happen to top.
class LeaderboardReportsController < ApplicationController
  include BlogStatsFilters

  # Shaped like the other list states, so changing the period or country
  # keeps the chosen order.
  Sort = Struct.new(:key) do
    def query
      key == Leaderboard::SORTS.keys.first ? {} : {sort: key}
    end
  end

  def show
    load_blog_stats
    @content = ContentStats.new(@stats, search: Google::SearchConsole::Summary.new(@period))
    @sort = Sort.new(params[:sort].presence_in(Leaderboard::SORTS.keys) || Leaderboard::SORTS.keys.first)
    leaderboard = Leaderboard.new(@content)
    @rows = leaderboard.rows(sort: @sort.key)

    respond_to do |format|
      format.html
      format.csv do
        send_csv leaderboard.to_csv(sort: @sort.key),
                 filename: "leaderboard-#{@period.from.iso8601}-to-#{@period.to.iso8601}.csv",
                 detail: "#{Leaderboard::SORTS[@sort.key]}, #{@period}"
      end
    end
  end
end
