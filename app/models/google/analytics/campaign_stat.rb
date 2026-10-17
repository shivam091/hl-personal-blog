# encoding: UTF-8

module Google
  module Analytics
    # Apart from sources, since a campaign is what the blog's own links
    # name themselves, so a newsletter's visits are told from any other
    # email's, and its links from each other.
    class CampaignStat
      include Mongoid::Document
      include Traffic

      field :campaign, type: String
      field :source, type: String
      field :medium, type: String
      field :content, type: String

      breakdown :campaign, :source, :medium, :content
    end
  end
end
