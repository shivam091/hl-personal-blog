# encoding: UTF-8

module Google
  module Analytics
    class LandingPageStat
      include Mongoid::Document
      include Traffic

      breakdown
    end
  end
end
