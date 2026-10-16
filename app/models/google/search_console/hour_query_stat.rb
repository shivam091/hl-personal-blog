# encoding: UTF-8

module Google
  module SearchConsole
    # So the queries a post starts ranking for show within hours of it going
    # out, before a whole day of them has been counted.
    # Site-wide only, since by page too would multiply the rows past use.
    class HourQueryStat
      include Mongoid::Document
      include Performance

      # The hour's start, as HourStat stores it.
      field :hour_at, type: Time
      field :query, type: String

      breakdown :hour_at, :query

      validates :hour_at, :query, presence: true
    end
  end
end
