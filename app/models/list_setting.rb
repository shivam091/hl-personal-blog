# encoding: UTF-8

# Kept on the server rather than in the browser, so a list looks the same
# on every device the admin signs in from. Backend-owned, so it may have
# its own index.
class ListSetting
  include Mongoid::Document
  include Mongoid::Timestamps

  # Every column the list had when saved, so a column added to the list
  # later can be told apart from one the admin hid.
  field :order, type: Array, default: []
  field :hidden, type: Array, default: []
  field :sort, type: String
  field :direction, type: String
  field :per_page, type: Integer
  field :tab, type: String
  field :density, type: String
  field :row_numbers, type: Boolean
  field :sticky_header, type: Boolean
  field :list, type: String

  index({list: 1}, unique: true)

  validates :list, presence: true, inclusion: {in: ->(_) { ListLayout.keys }}
  validates :direction, inclusion: {in: Sorting::DIRECTIONS}, allow_nil: true
  validates :per_page, inclusion: {in: Pagination::DEFAULT_PER_PAGE_OPTIONS}, allow_nil: true
end
