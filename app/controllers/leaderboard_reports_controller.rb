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
    @rows = Leaderboard.new(@content).rows(sort: @sort.key)
  end
end
