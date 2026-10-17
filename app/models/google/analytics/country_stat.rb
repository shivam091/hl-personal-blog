# encoding: UTF-8

module Google
  module Analytics
    class CountryStat
      include Mongoid::Document
      include Traffic

      # Coded as Search Console stats code countries, so the two line up
      # country for country.
      field :country, type: String

      breakdown :country, filtered: :country
    end
  end
end
