# encoding: UTF-8

module PaginationHelper
  # One shared pagination bar so every list pages the same way.
  def pagination_nav(pagination, keep: [])
    render "shared/pagination", pagination: pagination, keep: keep
  end
end
