# encoding: UTF-8

module Google
  module Analytics
    # Split by the title a page reported, because GA's own Pages and screens
    # report groups by title, and a page that sent the wrong title only shows
    # up when the two are compared.
    class PageTitleStat
      include Mongoid::Document
      include Traffic

      field :page_title, type: String

      breakdown :page_title
    end
  end
end
