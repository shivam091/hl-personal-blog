# encoding: UTF-8

module Google
  module SearchConsole
    # How much of a market searches on mobile differs country by country, so
    # a country's rankings on one device can't be read from countries and
    # devices stored apart.
    # Site-wide only, since by page too would multiply the rows past use.
    class CountryDeviceStat
      include Mongoid::Document
      include Performance

      # Coded and named as CountryStat and DeviceStat have them, so a row
      # here reads the same as there.
      field :country, type: String
      field :device, type: String

      breakdown :country, :device

      validates :country, :device, presence: true
    end
  end
end
