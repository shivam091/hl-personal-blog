# encoding: UTF-8

module Google
  module SearchConsole
    # So whether structured data pays off shows per rich result.
    class AppearanceStat
      include Mongoid::Document
      include Performance

      field :appearance, type: String

      breakdown :appearance

      validates :appearance, presence: true
    end
  end
end
