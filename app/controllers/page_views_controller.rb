# encoding: UTF-8

# So content decisions can follow real traffic.
class PageViewsController < ApplicationController
  include ListPeriodCounts

  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. /post/ or css-grid"),
    Filtering::DateRange.new(:updated, field: :updated_at, label: "Last updated")
  ].freeze
  # Each column starts in the direction most useful for it; busiest first by
  # default because that's what the page is for.
  SORT_COLUMNS = {
    "visitor_count" => "desc",
    "unique_visitor_count" => "desc",
    "url" => "asc",
    "updated_at" => "desc"
  }.freeze

  def index
    load_list_period
    respond_to do |format|
      format.html do
        @pagination = Pagination.new(filtered_page_views, params)
        @page_views = @pagination.records
      end
      format.csv do
        send_csv PageView.to_csv(filtered_page_views, period: (@period unless @period.all_time?)),
          filename: export_filename("page-views")
      end
    end
  end

  # Everything known about one page side by side, so whether it's found,
  # read and liked can be judged together.
  def show
    @page_view = PageView.find(params[:id])
    @period = Period.new(params)
    @granularity = ChartGranularity.new(params, period: @period)
    @page_like = PageLike.where(_id: @page_view.slug).first
    @search = Google::SearchConsole::Summary.new(@period)
    @analytics = Google::Analytics::Summary.new(@period)
    @ai = Google::SearchConsole::GenerativeAiSummary.new(@period)
    @views_since = PageView.first_day
    @likes_since = PageLike.first_day
    # Stored as full URLs, so they're matched on the path whatever the host.
    same_path = /\Ahttps?:\/\/[^\/]+#{Regexp.escape(@page_view.slug == "/" ? "" : @page_view.slug)}\/?\z/
    @feed_entry = FeedEntry.where(_id: same_path).first
    @crawled_page = CrawledPage.where(url: same_path).first
    @page_speed = Google::PageSpeed::Result.where(url: same_path).index_by(&:strategy)
    @launch_curve = LaunchCurve.new(@page_view, @feed_entry) if @feed_entry
    @like_rates = {"This page" => like_rate(@page_like&.like_count.to_i, @page_view.visitor_count),
                   "Site average" => like_rate(PageLike.sum(:likeCount), PageView.hit_totals[:humans])}
  end

  private

  # Per 100 views, since a share of one view in hundreds reads as nothing.
  # Withheld below the views a rate needs, as everywhere else.
  def like_rate(likes, views)
    (likes * 100.0 / views).round(2) if views >= BlogStats::MIN_VIEWS_FOR_RATE
  end

  def filtered_page_views
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS)
    # _id is the slug, so it's unique and keeps ties stable across pages.
    # Visitors aren't counted by day, so a span can't be sorted by them.
    @sorting = Sorting.new(params, columns: @period.all_time? ? SORT_COLUMNS : SORT_COLUMNS.except("unique_visitor_count"), tiebreaker: :_id)
    scope = @filtering.apply(PageView.all)
    return @sorting.apply(scope) if @period.all_time?

    sorted_within(scope, counted: "visitor_count") { |page_view| page_view.views_within(@period) }
  end
end
