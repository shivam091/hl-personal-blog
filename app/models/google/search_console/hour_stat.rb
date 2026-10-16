# encoding: UTF-8

module Google
  module SearchConsole
    # Search Console keeps hours for the last ten days or so only, so they're
    # copied to see how a post does in the hours after it's published or
    # updated, before a whole day of it has been counted.
    class HourStat
      include Mongoid::Document
      include Performance

      # Search Console counts its days and hours in Pacific Time, so an
      # hour is shown there, on the same day as the daily figures it adds up
      # to.
      TIME_ZONE = "America/Los_Angeles"

      # The hour's start, in UTC as every time is stored; its day is the
      # Pacific one.
      field :hour_at, type: Time

      # Read by the day and grouped by the hour, never matched on one.
      breakdown :hour_at, filtered: []

      validates :hour_at, presence: true

      class << self
        def label(hour_at)
          hour_at.in_time_zone(TIME_ZONE).strftime("%a %-d %b, %H:00")
        end
      end
    end
  end
end
