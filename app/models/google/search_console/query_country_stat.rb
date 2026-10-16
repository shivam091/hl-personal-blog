# encoding: UTF-8

module Google
  module SearchConsole
    # Queries and countries are each stored split by page alone, so what one
    # market searches can only be read from a report asked for by both.
    # Site-wide only, since by page too would multiply the rows past use.
    # The site's own query figures are these added up across countries,
    # which match them query for query and day for day, so they aren't
    # stored apart.
    class QueryCountryStat
      include Mongoid::Document
      include Performance

      field :query, type: String
      # Coded as CountryStat codes them, so a country searched on one reads
      # the same on the other.
      field :country, type: String

      # Narrowed to a country, whose queries are then listed, or added up
      # across them for the whole site's.
      breakdown :query, :country, filtered: :country, per_page: false

      validates :query, :country, presence: true
    end
  end
end
