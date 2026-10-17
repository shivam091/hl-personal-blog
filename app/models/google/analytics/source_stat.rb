# encoding: UTF-8

module Google
  module Analytics
    # So search, social and referral traffic can be told apart per post.
    class SourceStat
      include Mongoid::Document
      include Traffic

      field :channel_group, type: String
      field :source, type: String
      field :medium, type: String

      breakdown :channel_group, :source, :medium
    end
  end
end
