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

      # Stored for the whole site, since it's when readers are around that
      # matters, not when each page is read.
      breakdown :day_of_week, :hour, per_page: false
    end
  end
end
