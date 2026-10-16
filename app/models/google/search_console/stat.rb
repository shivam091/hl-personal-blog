# encoding: UTF-8

module Google
  module SearchConsole
    # Copied from Search Console because it only keeps 16 months and its UI
    # can't be joined with the blog's own traffic. A page's daily total is
    # stored as its own row because Google withholds rare queries for
    # privacy, so the per-query rows never add up to it.
    class Stat
      include Mongoid::Document
      include Performance

      field :query, type: String

      breakdown :query

      scope :page_totals, -> { per_page.where(query: nil) }
      scope :site_totals, -> { site_wide.where(query: nil) }
      scope :by_query, -> { where(:query.ne => nil) }
    end
  end
end
