# encoding: UTF-8

module Google
  module Analytics
    # Kept so the retention grid reads without a GA call once a week has
    # finished. Dated by the cohort's first week, since that's what names a
    # cohort and a finished week's figures only settle in place.
    class CohortWeekStat
      include Mongoid::Document
      include DailyStat

      field :week, type: Integer
      field :active_users, type: Integer, default: 0
      field :total_users, type: Integer, default: 0

      key_fields :week

      index({date: 1, week: 1}, {unique: true})

      validates :week, presence: true
    end
  end
end
