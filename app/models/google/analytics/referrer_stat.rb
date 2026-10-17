# encoding: UTF-8

module Google
  module Analytics
    # Kept because sources name only the referring site, not the exact page
    # that linked.
    class ReferrerStat
      include Mongoid::Document
      include Traffic

      field :referrer, type: String

      breakdown :referrer
    end
  end
end
