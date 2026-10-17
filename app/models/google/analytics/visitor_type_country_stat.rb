# encoding: UTF-8

module Google
  module Analytics
    # Readers coming back from one market and not another only shows with
    # the two asked of GA together, since VisitorTypeStat is stored by page
    # alone.
    class VisitorTypeCountryStat
      include Mongoid::Document
      include Traffic

      field :visitor_type, type: String
      # Coded as CountryStat codes countries, so the two line up.
      field :country, type: String

      breakdown :visitor_type, :country, filtered: :country
    end
  end
end
