# encoding: UTF-8

module Google
  module Analytics
    class LanguageStat
      include Mongoid::Document
      include Traffic

      field :language, type: String

      breakdown :language, per_page: false
    end
  end
end
