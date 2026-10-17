# encoding: UTF-8

module Google
  module Analytics
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
