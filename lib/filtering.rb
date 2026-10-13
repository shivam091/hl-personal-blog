# encoding: UTF-8

# Exists so every admin list can be narrowed the same way without each
# controller rebuilding search logic, and so the filter lives in the URL
# where it survives paging, sorting, and shared links. Fields are duck-typed
# so new kinds of search can be added without changing this class.
class Filtering
  attr_reader :fields, :tabs, :values, :tab

  def initialize(params, fields: [], tabs: nil)
    @fields = fields
    @tabs = tabs
    @values = fields.map { |field| field.read(params) }.reduce({}, :merge)
    @tab = tabs&.read(params)
  end

  # Kept apart from the tab so tab counts reflect the search without each
  # tab being narrowed by whichever tab is currently selected.
  def searched(scope)
    fields.reduce(scope) { |narrowed, field| field.apply(narrowed, values) }
  end

  def apply(scope)
    narrowed = searched(scope)
    tabs ? tabs.apply(narrowed, tab) : narrowed
  end

  def tab_counts(scope)
    tabs.counts(searched(scope))
  end

  def searching?
    values.values.any?
  end

  def filtered?
    searching? || tab.present?
  end

  def chips
    fields.flat_map { |field| field.chips(values) }
  end

  # So links that change sorting or paging don't drop the search and tab.
  def query
    search_query.merge(tabs ? {tabs.name => tab} : {}).compact
  end

  # Only some searches mean the same on another list, so only theirs are
  # carried to it.
  def query_for(shared)
    search_query.slice(*shared.flat_map { |field| field.read({}).keys })
  end

  # Dates must go back into the URL in the same form the fields read them.
  def search_query
    values.transform_values { |value| value.respond_to?(:iso8601) ? value.iso8601 : value }.compact
  end
end
