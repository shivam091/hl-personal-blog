# encoding: UTF-8

module Google
  module Analytics
    # So readers can be placed within a country. The country is kept beside
    # region and city because different countries share their names.
    class LocationStat
      include Mongoid::Document
      include Traffic

      # As in CountryStat, so the two line up country for country.
      field :country, type: String
      field :region, type: String
      field :city, type: String

      breakdown :country, :region, :city
    end
  end
end
