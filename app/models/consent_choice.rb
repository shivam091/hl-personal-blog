# encoding: UTF-8

# Counts per IST day rather than per reader, so a period's banner answers can be
# summed but never followed back to one reader.
class ConsentChoice
  include Mongoid::Document
  include ReadOnly

  # The frontend's name for it, which Mongoid's pluralised default wouldn't
  # find.
  store_in collection: "consent_choices"

  # A String to match how the frontend writes it, so reads don't mis-cast.
  field :day, type: String
  # Events rather than readers, so a reader shown the banner in two sessions counts twice.
  field :countries, type: Hash, default: {}
  field :createdAt, type: Time, as: :created_at
  field :updatedAt, type: Time, as: :updated_at

  class << self
    # ISO days sort as dates, so the period is compared as strings.
    def within(period)
      where(:day.gte => period.from.iso8601, :day.lte => period.to.iso8601)
    end

    # Recording began on some day, so a period reaching back before it shows
    # none rather than few.
    def first_day
      Date.iso8601(order(day: :asc).only(:day).first&.day.to_s)
    rescue Date::Error
      nil
    end
  end
end
