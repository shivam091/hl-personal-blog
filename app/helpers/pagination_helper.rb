# encoding: UTF-8

module PaginationHelper
  def pagination_nav(pagination, keep: [])
    render "shared/pagination", pagination: pagination, keep: keep
  end
end
