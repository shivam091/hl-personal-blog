# encoding: UTF-8

module Google
  module Analytics
    # Apart from age, since GA withholds a row that's too small to be
    # anonymous, and crossing the two would leave fewer rows above that.
    class GenderStat
      include Mongoid::Document
      include Traffic

      field :gender, type: String

      breakdown :gender, per_page: false
    end
  end
end
