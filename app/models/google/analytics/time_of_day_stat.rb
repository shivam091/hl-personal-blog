# encoding: UTF-8

module Google
  module Analytics
    # So a post can go out when readers are around.
    class TimeOfDayStat
      include Mongoid::Document
      include Traffic

      # Kept as the strings GA gives, so they sort in time order.
      field :day_of_week, type: String
      field :hour, type: String

      breakdown :day_of_week, :hour
    end
  end
end
