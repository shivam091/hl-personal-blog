# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from sources by page, because a session's source belongs to
    # the page it began on: split by every page it touched, a post read after
    # arriving elsewhere is credited with traffic it didn't bring.
    class LandingSourceStat
      include Mongoid::Document
      include Traffic

      field :channel_group, type: String
      field :source, type: String
      field :medium, type: String

      breakdown :channel_group, :source, :medium
    end
  end
end
