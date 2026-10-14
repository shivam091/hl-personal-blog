# encoding: UTF-8

# A list's columns as config/list_layouts.yml defines them, with the admin's
# saved choices laid over them. Saved choices are checked against the file
# on every read, so renaming or dropping a column there can't break a list
# that was customized before.
class ListLayout
  DENSITIES = %w[comfortable compact].freeze

  Column = Data.define(:key, :label, :sort, :required, :align) do
    def sortable?
      sort.present?
    end
  end

  attr_reader :key, :label, :route, :setting

  class << self
    # Read on every request rather than at boot, so editing the file shows up
    # without a restart; it's tiny, so this costs nothing.
    def definitions
      Rails.application.config_for(:list_layouts).stringify_keys
    end

    def keys
      definitions.keys
    end

    def find(key)
      key = key.to_s
      definition = definitions.fetch(key) { raise Mongoid::Errors::DocumentNotFound.new(ListSetting, list: key) }
      new(key, definition, ListSetting.where(list: key).first)
    end

    # One query for every list's setting, rather than one per list.
    def all
      settings = ListSetting.where(:list.in => keys).index_by(&:list)
      definitions.map { |key, definition| new(key, definition, settings[key]) }
    end
  end

  def initialize(key, definition, setting = nil)
    @key = key
    @label = definition.fetch(:label)
    @route = definition.fetch(:route)
    @default_sort = definition[:sort].to_s
    @tabs_constant = definition[:tabs]
    @definitions = definition.fetch(:columns).to_h do |column_key, column|
      column_key = column_key.to_s
      [column_key, Column.new(key: column_key, label: column.fetch(:label), sort: column[:sort], required: column[:required] == true, align: column[:align])]
    end
    @setting = setting
  end

  def customized?
    setting.present?
  end

  # Columns added to the file since the setting was saved go last, shown,
  # so a new column is noticed rather than silently missing.
  def columns
    saved = Array(setting&.order).filter_map { |column_key| @definitions[column_key] }
    saved | @definitions.values
  end

  def visible_columns
    columns.reject { |column| hidden?(column) }
  end

  def hidden_columns
    columns.select { |column| hidden?(column) }
  end

  def hidden?(column)
    !column.required && Array(setting&.hidden).include?(column.key)
  end

  def sortable_columns
    @definitions.values.select(&:sortable?)
  end

  def default_sort
    column = @definitions[setting&.sort] || @definitions[@default_sort] || sortable_columns.first
    [column&.key, setting&.direction.presence_in(Sorting::DIRECTIONS) || column&.sort]
  end

  def default_per_page
    setting&.per_page.presence_in(Pagination::DEFAULT_PER_PAGE_OPTIONS) || Pagination::DEFAULT_PER_PAGE_OPTIONS.first
  end

  # Named in the file rather than repeated there, so a tab's label and
  # filter stay defined once, beside the list that applies them.
  def tabs
    @tabs_constant&.constantize
  end

  def default_tab
    setting&.tab.presence_in(Array(tabs&.choices&.keys))
  end

  def density
    setting&.density.presence_in(DENSITIES) || DENSITIES.first
  end

  def compact?
    density == "compact"
  end

  def row_numbers?
    setting&.row_numbers != false
  end

  def sticky_header?
    setting&.sticky_header == true
  end

  def sorting(params, tiebreaker: :_id)
    columns = sortable_columns.to_h { |column| [column.key, column.sort] }
    Sorting.new(params, columns: columns, tiebreaker: tiebreaker, default: default_sort)
  end

  def pagination(scope, params)
    Pagination.new(scope, params, default_per_page: default_per_page)
  end

  def filtering(params, fields: [])
    Filtering.new(params, fields: fields, tabs: tabs, default_tab: default_tab)
  end

  # Only known columns, sorts, tabs and page sizes are kept, since the form
  # posts whatever the browser sends. A choice that matches the file's own
  # defaults is dropped rather than stored, so the list keeps following the
  # file and shows as not customized.
  def save(choices)
    order = (Array(choices[:shown]) + Array(choices[:hidden])).map(&:to_s) & @definitions.keys
    order |= @definitions.keys
    hidden = (Array(choices[:hidden]).map(&:to_s) & order).reject { |column_key| @definitions[column_key].required }

    attributes = {
      order: order,
      hidden: hidden,
      sort: choices[:sort].to_s.presence_in(sortable_columns.map(&:key)),
      direction: choices[:direction].to_s.presence_in(Sorting::DIRECTIONS),
      per_page: choices[:per_page].to_i.presence_in(Pagination::DEFAULT_PER_PAGE_OPTIONS),
      tab: choices[:tab].to_s.presence_in(Array(tabs&.choices&.keys)),
      density: choices[:density].to_s.presence_in(DENSITIES) || DENSITIES.first,
      row_numbers: ActiveModel::Type::Boolean.new.cast(choices[:row_numbers]) != false,
      sticky_header: ActiveModel::Type::Boolean.new.cast(choices[:sticky_header]) == true
    }
    return reset! if attributes == defaults

    @setting ||= ListSetting.new(list: key)
    @setting.update!(attributes)
  end

  def reset!
    setting&.destroy
    @setting = nil
  end

  private

  def defaults
    column = @definitions[@default_sort] || sortable_columns.first
    {order: @definitions.keys, hidden: [], sort: column&.key, direction: column&.sort,
     per_page: Pagination::DEFAULT_PER_PAGE_OPTIONS.first, tab: nil, density: DENSITIES.first,
     row_numbers: true, sticky_header: false}
  end
end
