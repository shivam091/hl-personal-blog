# encoding: UTF-8

class PageViewsController < ApplicationController
  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. /post/ or css-grid"),
    Filtering::DateRange.new(:updated, field: :updated_at, label: "Last updated")
  ].freeze
  SORT_COLUMNS = {
    "visitor_count" => "desc",
    "unique_visitor_count" => "desc",
    "url" => "asc",
    "updated_at" => "desc"
  }.freeze

  def index
    respond_to do |format|
      format.html do
        @pagination = Pagination.new(filtered_page_views, params)
        @page_views = @pagination.records
      end
      format.csv do
        send_csv PageView.to_csv(filtered_page_views),
          filename: "page-views-#{Date.current.iso8601}.csv"
      end
    end
  end

  def show
    @page_view = PageView.find(params[:id])
    @period = Period.new(params)
    @page_like = PageLike.where(_id: @page_view.slug).first
    # Stored as full URLs, so they're matched on the path whatever the host.
    same_path = /\Ahttps?:\/\/[^\/]+#{Regexp.escape(@page_view.slug == "/" ? "" : @page_view.slug)}\/?\z/
    @feed_entry = FeedEntry.where(_id: same_path).first
    @crawled_page = CrawledPage.where(url: same_path).first
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
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    @sorting.apply(@filtering.apply(PageView.all))
  end
end
