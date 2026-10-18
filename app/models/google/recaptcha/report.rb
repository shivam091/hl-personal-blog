# encoding: UTF-8

module Google
  module Recaptcha
    # For one action as well as overall, so a spike can be traced to the
    # form it hit and a threshold judged on whom it would turn away.
    class Report
      TOP_ACTIONS = 10

      attr_reader :period, :action

      # The period compared with is read for the same action, so a chart
      # answers one question; without its stats there's nothing to read
      # against.
      def initialize(stats, period:, action: nil, previous: nil)
        @stats = stats
        @period = period
        @action = action.presence_in(actions)
        @previous = previous
      end

      def compared?
        !@previous.nil?
      end

      # Every action scored in the period, so one with no traffic since isn't
      # offered.
      def actions
        @actions ||= @stats.flat_map { |stat| stat.action_scores.keys }.uniq.sort
      end

      # Kept in the URL, so paging the table or another period keeps the
      # action charted.
      def query
        {recaptcha_action: action}.compact
      end

      def requests
        @stats.sum { |stat| count(buckets(stat)) }
      end

      # A day Google returned nothing for is a gap rather than zero, since it
      # may not have been synced.
      def daily
        by_date = @stats.index_by(&:date)
        @daily ||= (period.from..period.to).map do |date|
          stat = by_date[date]
          next [date, nil, nil] unless stat

          day = buckets(stat)
          low = day.sum { |bucket| bucket["score"] < Stat::LOW_SCORE ? bucket["count"] : 0 }
          [date, low, count(day) - low]
        end
      end

      # Day for day, as the trend charts read a comparison, so a month is
      # read against the month before whatever their lengths.
      def previous_daily
        return unless compared?

        by_date = @previous.index_by(&:date)
        (period.previous.from..period.previous.to).first(daily.size).map do |date|
          stat = by_date[date]
          count(buckets(stat)) if stat
        end
      end

      # At the same place in the period compared with as the chart reads it,
      # so a row and its bar answer alike; nil where that day wasn't synced,
      # since it would read as a jump from zero.
      def previous_day(date)
        return unless compared?

        day = period.previous.from + (date - period.from).to_i
        @previous_by_date ||= @previous.index_by(&:date)
        @previous_by_date[day] if day <= period.previous.to
      end

      # Only checkbox keys are challenged, so a score-only key has nothing to
      # chart; and challenges aren't split by action, so these are always the
      # whole site's.
      def challenged?
        @stats.any? { |stat| stat.challenges.except("page_loads").values.any?(&:positive?) }
      end

      def daily_challenges
        by_date = @stats.index_by(&:date)
        (period.from..period.to).map do |date|
          challenges = by_date[date]&.challenges
          next [date, nil, nil, nil] if challenges.blank?

          [date, *%w[no_challenge passed failed].map { |name| challenges[name].to_i }]
        end
      end

      # Of the challenges actually solved or failed, since one never shown
      # says nothing about who could solve it.
      def challenge_pass_rate
        passed = @stats.sum { |stat| stat.challenges["passed"].to_i }
        failed = @stats.sum { |stat| stat.challenges["failed"].to_i }
        passed.fdiv(passed + failed) if (passed + failed).positive?
      end

      def histogram
        counts = Hash.new(0)
        @stats.each { |stat| buckets(stat).each { |bucket| counts[bucket["score"].to_f.round(1)] += bucket["count"].to_i } }
        Summary::BUCKETS.to_h { |score| [score, counts[score]] }
      end

      # Every action whatever's charted, since they're the choices. Each
      # comes with the total of all actions, so a share is of every one of
      # them rather than of the top few.
      def top_actions
        ranked { |buckets| count(buckets) }
      end

      def top_suspicious_actions
        ranked { |buckets| suspicious(buckets) }
      end

      # Every action's, not just the ranked ones', so an action new to the
      # period reads as new rather than as missing.
      def previous_actions
        by_action(@previous) { |buckets| count(buckets) } if compared?
      end

      def previous_suspicious_actions
        by_action(@previous) { |buckets| suspicious(buckets) } if compared?
      end

      private

      def buckets(stat)
        action ? Array(stat.action_scores[action]) : stat.scores
      end

      def count(buckets)
        buckets.sum { |bucket| bucket["count"].to_i }
      end

      def suspicious(buckets)
        buckets.sum { |bucket| bucket["score"] < Stat::LOW_SCORE ? bucket["count"] : 0 }
      end

      def ranked(&block)
        totals = by_action(@stats, &block)
        [totals.select { |_, total| total.positive? }.sort_by { |name, total| [-total, name] }.first(TOP_ACTIONS), totals.values.sum]
      end

      def by_action(stats)
        totals = Hash.new(0)
        stats.each { |stat| stat.action_scores.each { |name, buckets| totals[name] += yield(buckets) } }
        totals
      end
    end
  end
end
