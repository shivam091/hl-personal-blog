# encoding: UTF-8

module Google
  module Analytics
    # So a post's readers can be set against its search performance in each
    # market.
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
