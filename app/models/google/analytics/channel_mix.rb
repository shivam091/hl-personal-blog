# encoding: UTF-8

module Google
  module Analytics
    # Each channel's share of sessions over time, so a shift in where readers
    # come from shows even while the totals hold steady. Sessions, as GA's
    # channel reports count them, since a channel brings visits, not views.
    class ChannelMix
      # As the blog's country shares are cut, so the two read alike.
      WEEKLY_UP_TO_DAYS = 120

      def initialize(criteria, period, limit: 5)
        @criteria = criteria
        @period = period
        @limit = limit
      end

      def shares
        weekly = @period.days <= WEEKLY_UP_TO_DAYS
        rows = @criteria.collection.aggregate([
          {"$match" => @criteria.selector},
          {"$group" => {
            "_id" => {"date" => "$date", "channel" => "$channel_group"},
            "sessions" => {"$sum" => "$sessions"}}
          }
        ]).to_a
        totals = rows.each_with_object(Hash.new(0)) { |row, sums| sums[row["_id"]["channel"]] += row["sessions"].to_i }
        top = totals.reject { |_, sessions| sessions.zero? }.sort_by do |channel, sessions|
          [-sessions, channel.to_s]
        end.first(@limit).map(&:first)
        buckets = Hash.new { |hash, start| hash[start] = Hash.new(0) }
        rows.each do |row|
          date = row["_id"]["date"].to_date
          channel = row["_id"]["channel"]
          buckets[weekly ? date.beginning_of_week : date.beginning_of_month][top.include?(channel) ? channel : :other] += row["sessions"].to_i
        end
        {keys: top, unit: weekly ? :week : :month, buckets: buckets.sort.to_h}
      end
    end
  end
end
