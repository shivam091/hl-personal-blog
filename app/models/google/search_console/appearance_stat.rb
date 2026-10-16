# encoding: UTF-8

module Google
  module SearchConsole
    class AppearanceStat
      include Mongoid::Document
      include Performance

      field :appearance, type: String

      breakdown :appearance

      validates :appearance, presence: true
    end
  end
end
