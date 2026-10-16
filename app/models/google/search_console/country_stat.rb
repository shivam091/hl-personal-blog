# encoding: UTF-8

module Google
  module SearchConsole
    # So rankings and click-through can be told apart by market.
    class CountryStat
      include Mongoid::Document
      include Performance

      # Coded as Analytics stats code countries, so the two line up country
      # for country.
      field :country, type: String

      breakdown :country

      validates :country, presence: true
    end
  end
end
