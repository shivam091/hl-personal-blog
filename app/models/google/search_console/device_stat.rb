# encoding: UTF-8

module Google
  module SearchConsole
    # Split by device because Google ranks mobile and desktop results
    # separately.
    class DeviceStat
      include Mongoid::Document
      include Performance

      # Named as Analytics stats name devices, so the two line up.
      field :device, type: String

      breakdown :device

      validates :device, presence: true
    end
  end
end
