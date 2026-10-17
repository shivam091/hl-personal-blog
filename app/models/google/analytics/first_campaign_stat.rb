# encoding: UTF-8

module Google
  module Analytics
    # Kept apart from first-user sources, whose rows are keyed without a
    # campaign, so which tagged link first brought new readers in reads apart
    # from the sessions a campaign got later.
    class FirstCampaignStat
      include Mongoid::Document
      include Traffic

      field :first_campaign, type: String
      field :first_source, type: String
      field :first_medium, type: String

      breakdown :first_campaign, :first_source, :first_medium
    end
  end
end
