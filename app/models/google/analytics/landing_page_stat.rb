# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from a page's own traffic because it shows which posts bring
    # people to the site rather than which ones they read once there.
    class LandingPageStat
      include Mongoid::Document
      include Traffic

      breakdown
    end
  end
end
