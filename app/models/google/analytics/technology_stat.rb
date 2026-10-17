# encoding: UTF-8

module Google
  module Analytics
    class TechnologyStat
      include Mongoid::Document
      include Traffic

      field :browser, type: String
      field :operating_system, type: String

      breakdown :browser, :operating_system, per_page: false
    end
  end
end
