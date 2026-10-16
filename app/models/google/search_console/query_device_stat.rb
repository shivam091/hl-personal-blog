# encoding: UTF-8

module Google
  module SearchConsole
    # Google ranks mobile and desktop apart, so a query can rank on one and
    # not the other, which neither queries nor devices alone show.
    # Site-wide only, since by page too would multiply the rows past use.
    class QueryDeviceStat
      include Mongoid::Document
      include Performance

      field :query, type: String
      field :device, type: String

      breakdown :query, :device

      validates :query, :device, presence: true
    end
  end
end
