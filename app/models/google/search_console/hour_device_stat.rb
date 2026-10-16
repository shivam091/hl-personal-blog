# encoding: UTF-8

module Google
  module SearchConsole
    # Google ranks mobile and desktop apart, so a post's first hours can rank
    # on one before the other.
    # Site-wide only, since by page too would multiply the rows past use.
    class HourDeviceStat
      include Mongoid::Document
      include Performance

      # The hour's start, as HourStat stores it.
      field :hour_at, type: Time
      # Named as DeviceStat names them, so a device reads the same on both.
      field :device, type: String

      breakdown :hour_at, :device

      validates :hour_at, :device, presence: true
    end
  end
end
