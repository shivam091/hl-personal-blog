# encoding: UTF-8

# Exists so every admin list sorts the same way from the URL, while only
# whitelisted columns are allowed so request params can't order by
# arbitrary (or unindexed) fields.
class Sorting
  DIRECTIONS = %w[asc desc].freeze

  attr_reader :columns, :column, :direction, :tiebreaker

  def initialize(params, columns:, tiebreaker: :_id)
    @columns = columns
    @tiebreaker = tiebreaker
    @column = params[:sort].presence_in(columns.keys) || default_column
    @direction = params[:direction].presence_in(DIRECTIONS) || columns[@column]
  end

  def apply(scope)
    # The tiebreaker keeps equal values in a stable order across pages, but
    # must not override the chosen direction when it is the sort column too.
    order = {column.to_s => direction}
    order[tiebreaker.to_s] ||= "asc"
    scope.order(order)
  end

  def sorted_by?(column)
    self.column == column
  end

  # So links that change filtering or paging don't drop the sort, while the
  # default sort keeps URLs clean.
  def query
    default? ? {} : {sort: column, direction: direction}
  end

  # Lets one header click both pick a column and reverse it, starting in the
  # direction that's most useful for that column.
  def toggle_query(column)
    next_direction =
      if sorted_by?(column)
        direction == "asc" ? "desc" : "asc"
      else
        columns.fetch(column)
      end
    {sort: column, direction: next_direction}
  end

  # So screen readers announce which column the list is sorted by.
  def aria_sort(column)
    return "none" unless sorted_by?(column)

    direction == "asc" ? "ascending" : "descending"
  end

  private

  def default_column
    columns.keys.first
  end

  def default?
    column == default_column && direction == columns[column]
  end
end
