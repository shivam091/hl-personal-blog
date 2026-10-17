# encoding: UTF-8

module Google
  module Analytics
    # So a layout bug confined to one browser shows up as that browser's
    # engagement dropping.
    class TechnologyStat
      include Mongoid::Document
      include Traffic

      field :browser, type: String
      field :operating_system, type: String

      breakdown :browser, :operating_system, per_page: false
    end
  end
end
