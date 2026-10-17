# encoding: UTF-8

module Google
  module Analytics
    # Apart from gender, since GA withholds a row that's too small to be
    # anonymous, and crossing the two would leave fewer rows above that.
    class AgeStat
      include Mongoid::Document
      include Traffic

      field :age_bracket, type: String

      breakdown :age_bracket, per_page: false
    end
  end
end
