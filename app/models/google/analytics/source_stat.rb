# encoding: UTF-8

module Google
  module Analytics
    # Sessions by channel, source and medium, and by the campaign a tagged
    # link named, in one report: Sources adds the campaigns up, and Campaigns
    # reads only the tagged rows, so a newsletter's visits are told from any
    # other email's, and its links from each other.
    class SourceStat
      include Mongoid::Document
      include Traffic

      field :channel_group, type: String
      field :source, type: String
      field :medium, type: String
      # GA's own word for a session no campaign was named for, so a row
      # saved without one still has a key.
      field :campaign, type: String, default: "(not set)"
      field :content, type: String, default: "(not set)"

      breakdown :channel_group, :source, :medium, :campaign, :content
    end
  end
end
