# encoding: UTF-8

module Google
  module Analytics
    # A page's traffic, split by the title it reported and whether its readers
    # were new or returning, in one report: Pages and screens adds the splits
    # up, Page titles reads by title, and New vs returning by visitor type, so
    # none of them needs a copy of the others' rows. Nearly every page has one
    # title and one kind of reader a day, so the splits add few rows.
    class Stat
      include Mongoid::Document
      include Traffic

      # GA's own word for a figure it couldn't place, so a row saved without
      # a split still has a key.
      field :page_title, type: String, default: "(not set)"
      field :visitor_type, type: String, default: "(not set)"

      breakdown :page_title, :visitor_type

      class << self
        # Views rather than users, since a reader is counted again on every
        # day and page they're stored for, while views add up. Weeks start on
        # Monday, as the blog's own do.
        def weekly_views(period)
          criteria = period.apply(all)
          counts = collection.aggregate([
            {"$match" => criteria.selector},
            {"$group" => {"_id" => {"date" => "$date", "type" => "$visitor_type"}, "views" => {"$sum" => "$views"}}}
          ]).each_with_object(Hash.new { |hash, type| hash[type] = Hash.new(0) }) do |row, sums|
            sums[row["_id"]["type"].presence || "(not set)"][row["_id"]["date"].to_date.beginning_of_week] += row["views"].to_i
          end
          weeks = (period.from.beginning_of_week..period.to).step(7).to_a
          {weeks: weeks, views: counts.to_h { |type, by_week| [type, weeks.map { |week| by_week[week] }] }}
        end
      end
    end
  end
end
