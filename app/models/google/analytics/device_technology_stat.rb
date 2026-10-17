# encoding: UTF-8

module Google
  module Analytics
    # A browser's share means little without the device it runs on, and
    # TechnologyStat isn't stored by device.
    class DeviceTechnologyStat
      include Mongoid::Document
      include Traffic

      # Named as DeviceStat names devices, so the two line up.
      field :device, type: String
      field :browser, type: String
      field :operating_system, type: String

      breakdown :device, :browser, :operating_system, filtered: :device
    end
  end
end
