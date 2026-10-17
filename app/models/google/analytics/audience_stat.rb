# encoding: UTF-8

module Google
  module Analytics
    # Each page's traffic by device, place and referring page in one report,
    # read by any of them: at the blog's traffic a page's readers a day mostly
    # share all three, so one row holds what a report split by each would
    # repeat. Countries, regions and cities, devices and referrers are each
    # these rows added up.
    class AudienceStat
      include Mongoid::Document
      include Traffic

      # Named as Search Console stats name devices, and coded as they code
      # countries, so the two line up.
      field :device, type: String, default: "(not set)"
      field :country, type: String, default: "ZZ"
      # The country is kept beside region and city because different
      # countries share their names.
      field :region, type: String, default: "(not set)"
      field :city, type: String, default: "(not set)"
      # The exact page that linked, which sources, naming only the site,
      # don't say.
      field :referrer, type: String, default: "(not set)"

      breakdown :device, :country, :region, :city, :referrer, filtered: %i[device country]
    end
  end
end
