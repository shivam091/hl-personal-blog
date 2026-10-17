# encoding: UTF-8

module Google
  module Analytics
    # The country is kept beside region and city because different countries share
    # their names.
    class LocationStat
      include Mongoid::Document
      include Traffic

      # As in CountryStat, so the two line up country for country.
      field :country, type: String
      field :region, type: String
      field :city, type: String

      # Stored for the whole site, since where readers are matters more than
      # which page each place read.
      breakdown :country, :region, :city, per_page: false
    end
  end
end
