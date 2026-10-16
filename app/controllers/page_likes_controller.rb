# encoding: UTF-8

class PageLikesController < ApplicationController
  include ListPeriodCounts

  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. /post/ or css-grid"),
    Filtering::DateRange.new(:liked, field: :updated_at, label: "Last liked")
  ].freeze
  SORT_COLUMNS = {
    "like_count" => "desc",
    "url" => "asc",
    "updated_at" => "desc",
    "created_at" => "desc"
  }.freeze

  def index
    load_list_period
    respond_to do |format|
      format.html do
        @pagination = Pagination.new(filtered_page_likes, params)
        @page_likes = @pagination.records
      end
      format.csv do
        send_csv PageLike.to_csv(filtered_page_likes, period: (@period unless @period.all_time?)),
          filename: export_filename("page-likes")
      end
    end
  end

  def show
    @page_like = PageLike.find(params[:id])
  end

  private

  def filtered_page_likes
    @filtering = Filtering.new(params, fields: SEARCH_FIELDS)
    # _id is the slug, so it's unique and keeps ties stable across pages.
    @sorting = Sorting.new(params, columns: SORT_COLUMNS, tiebreaker: :_id)
    scope = @filtering.apply(PageLike.all)
    return @sorting.apply(scope) if @period.all_time?

    sorted_within(scope, counted: "like_count") { |page_like| page_like.likes_within(@period) }
  end
end
