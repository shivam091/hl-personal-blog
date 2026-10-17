# encoding: UTF-8

module Google
  module Analytics
    # So a post that reads badly on phones shows up as weaker mobile
    # engagement.
    class DeviceStat
      include Mongoid::Document
      include Traffic

      # Named as Search Console stats name devices, so the two line up.
      field :device, type: String

      breakdown :device, filtered: :device
    end
  end
end
