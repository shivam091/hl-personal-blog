# encoding: UTF-8

# A list's search, tab and sort under a name, so a view used often is one
# click rather than a form refilled each time. Kept apart from the list's
# layout, so resetting the layout doesn't lose them.
class SavedSearch
  include Mongoid::Document
  include Mongoid::Timestamps

  field :list, type: String
  field :name, type: String
  # As a query string, re-read through Rack on the way out, so a stored
  # value can't steer url_for to another host or controller.
  field :query, type: String

  index({list: 1, name: 1}, unique: true)

  validates :list, presence: true, inclusion: {in: ->(_) { ListLayout.keys }}
  validates :name, presence: true, length: {maximum: 40}, uniqueness: {scope: :list}
  validates :query, presence: true, length: {maximum: 2_000}

  def self.for(list)
    where(list: list).order(name: :asc)
  end

  def params
    Rack::Utils.parse_nested_query(query).select { |_key, value| value.is_a?(String) }
  end

  def to_s
    name
  end
end
