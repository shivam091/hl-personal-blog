# encoding: UTF-8

module Google
  module SearchConsole
    # Google ranks mobile and desktop apart in every market, so how a query
    # does on one device in one country shows only in a report asked for by
    # all three.
    # Site-wide only, since by page too would multiply the rows past use.
    class QueryCountryDeviceStat
      include Mongoid::Document
      include Performance

      field :query, type: String
      # Coded and named as CountryStat and DeviceStat have them, so a row
      # here reads the same as there.
      field :country, type: String
      field :device, type: String

      breakdown :query, :country, :device

      validates :query, :country, :device, presence: true
    end
  end
end
