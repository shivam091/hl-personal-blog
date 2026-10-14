# encoding: UTF-8

# A like is a stronger signal than a view, so likes show what's worth
# writing more of.
class PageLikesController < ApplicationController
  SEARCH_FIELDS = [
    Filtering::Contains.new(:q, field: :url, label: "URL contains", placeholder: "e.g. /post/ or css-grid"),
    Filtering::DateRange.new(:liked, field: :updated_at, label: "Last liked")
  ].freeze
  # Each column starts in the direction most useful for it; most liked first
  # by default because that's what the page is for.
  SORT_COLUMNS = {
    "like_count" => "desc",
    "url" => "asc",
    "updated_at" => "desc",
    "created_at" => "desc"
  }.freeze

  def index
    respond_to do |format|
      format.html do
        @pagination = Pagination.new(filtered_page_likes, params)
        @page_likes = @pagination.records
      end
      format.csv do
        send_csv PageLike.to_csv(filtered_page_likes),
          filename: "page-likes-#{Date.current.iso8601}.csv"
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
    @sorting.apply(@filtering.apply(PageLike.all))
  end
end
