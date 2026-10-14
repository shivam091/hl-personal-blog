# encoding: UTF-8

# The frontend keys its daily counts by ISO day inside each page's document,
# so the earliest day has to be found across every page's keys.
module DatedByDay
  extend ActiveSupport::Concern

  DAY = {"$regex" => "^\\d{4}-\\d{2}-\\d{2}$"}.freeze

  class_methods do
    # Found in the database, since every page would otherwise be loaded just
    # to read one date.
    def first_day_in(fields)
      days = fields.map { |field| {"$map" => {"input" => {"$objectToArray" => {"$ifNull" => ["$#{field}", {}]}}, "in" => "$$this.k"}} }
      row = collection.aggregate([
        {"$project" => {"day" => {"$concatArrays" => days}}},
        {"$unwind" => "$day"},
        # A day the frontend wrote oddly would otherwise sort first.
        {"$match" => {"day" => DAY}},
        {"$group" => {"_id" => nil, "first" => {"$min" => "$day"}}}
      ]).first
      Date.iso8601(row["first"]) if row
    rescue Date::Error
      nil
    end
  end
end
