# encoding: UTF-8

module Google
  module Analytics
    # Kept because users and sessions summed over pages count a reader once
    # per page they read, so only GA's own whole-site row says how many came
    # on a day.
    class SiteDayStat
      include Mongoid::Document
      include Traffic

      # GA's rolling actives, kept per day since each already counts the
      # readers of the days before it. Never summed across days, which would
      # count the same reader up to 28 times.
      ROLLING = {active_1_day_users: "active1DayUsers", active_7_day_users: "active7DayUsers", active_28_day_users: "active28DayUsers"}.freeze

      ROLLING.each_key { |count| field count, type: Integer, default: 0 }

      breakdown per_page: false
    end
  end
end
