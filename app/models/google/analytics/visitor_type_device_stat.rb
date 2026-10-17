# encoding: UTF-8

module Google
  module Analytics
    # Whether readers come back on the device they found the blog on only
    # shows with the two asked of GA together, since VisitorTypeStat is
    # stored by page alone.
    class VisitorTypeDeviceStat
      include Mongoid::Document
      include Traffic

      field :visitor_type, type: String
      # Named as DeviceStat names devices, so the two line up.
      field :device, type: String

      breakdown :visitor_type, :device, filtered: :device
    end
  end
end
