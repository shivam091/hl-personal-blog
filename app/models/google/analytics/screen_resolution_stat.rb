# encoding: UTF-8

module Google
  module Analytics
    # So the widths worth checking a layout at are the ones readers use,
    # since a device category alone hides how wide its screens are.
    class ScreenResolutionStat
      include Mongoid::Document
      include Traffic

      field :screen_resolution, type: String

      breakdown :screen_resolution
    end
  end
end
