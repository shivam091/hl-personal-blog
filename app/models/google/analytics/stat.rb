# encoding: UTF-8

module Google
  module Analytics
    class Stat
      include Mongoid::Document
      include Traffic

      breakdown
    end
  end
end
