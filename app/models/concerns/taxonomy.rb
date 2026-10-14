# encoding: UTF-8

# Tags and categories only ever come from the feed or a CSV, by name, so
# whatever a source names is created on first sight rather than rejected.
module Taxonomy
  extend ActiveSupport::Concern

  MAX_NAME_LENGTH = 100

  included do
    include Mongoid::Timestamps
    include StripAttribute

    field :name, type: String

    index({name: 1}, {unique: true})

    strip_attributes! :name

    validates :name, presence: true, uniqueness: true, length: {maximum: MAX_NAME_LENGTH}
  end

  def to_s
    name
  end

  class_methods do
    # In bulk, so syncing doesn't cost a round trip to Atlas per tag per
    # entry. A name that can't be saved is skipped rather than raised, so
    # it doesn't stop the entries that use it from syncing.
    def ids_by_name(names, errors)
      names = names.map(&:strip).compact_blank.uniq
      ids = where(:name.in => names).pluck(:name, :_id).to_h

      (names - ids.keys).each do |name|
        record = new(name: name)
        if record.save
          ids[name] = record.id
        else
          errors << "#{model_name.human} #{name.inspect}: #{record.errors.full_messages.to_sentence}"
        end
      rescue Mongo::Error::OperationFailure => e
        # A concurrent sync created it first; that one is just as good.
        raise unless e.code == 11000 # duplicate key

        ids[name] = find_by(name: name).id
      end

      ids
    end

    def names
      order(name: :asc).pluck(:name)
    end
  end
end
