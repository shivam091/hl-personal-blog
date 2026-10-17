# encoding: UTF-8

module Google
  module Analytics
    # So readers who'd rather read in another language show up before
    # anything is translated for them.
    class LanguageStat
      include Mongoid::Document
      include Traffic

      field :language, type: String

      breakdown :language
    end
  end
end
