# encoding: UTF-8

module Google
  module Analytics
    class ScreenResolutionStat
      include Mongoid::Document
      include Traffic

      field :screen_resolution, type: String

      breakdown :screen_resolution, per_page: false
    end
  end
end
