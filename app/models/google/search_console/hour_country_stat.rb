# encoding: UTF-8

module Google
  module SearchConsole
    # So a post's first hours can be read market by market, before a whole
    # day of them has been counted.
    # Site-wide only, since by page too would multiply the rows past use.
    class HourCountryStat
      include Mongoid::Document
      include Performance

      # The hour's start, as HourStat stores it.
      field :hour_at, type: Time
      # Coded as CountryStat codes them, so a country reads the same on both.
      field :country, type: String

      breakdown :hour_at, :country

      validates :hour_at, :country, presence: true
    end
  end
end
