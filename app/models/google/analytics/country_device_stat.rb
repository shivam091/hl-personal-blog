# encoding: UTF-8

module Google
  module Analytics
    # Countries and devices are each stored by page alone, so what one
    # market reads on needs the two asked of GA together.
    class CountryDeviceStat
      include Mongoid::Document
      include Traffic

      # Coded and named as CountryStat and DeviceStat, so the three line up.
      field :country, type: String
      field :device, type: String

      breakdown :country, :device, filtered: %i[country device]
    end
  end
end
