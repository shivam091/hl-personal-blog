# encoding: UTF-8

module Google
  module Recaptcha
    # Takes stats already narrowed to an action when one is picked, so the
    # action is only carried for links and labels.
    class Report
      TOP_ACTIONS = 10

      attr_reader :period, :action

      def initialize(stats, period:, action: nil, previous: nil)
        @stats = stats
        @period = period
        @action = action
        @previous = previous
      end

      def compared?
        !@previous.nil?
      end

      # Every action scored in the period, so one with no traffic since isn't
      # ranked; none once narrowed to one, since a ranking of one says nothing.
      def actions
        @actions ||= @stats.flat_map { |stat| stat.action_scores.keys }.uniq.sort
      end

      def query
        {recaptcha_action: action}.compact
      end

      def requests
        @stats.sum { |stat| count(stat.scores) }
      end

      # A day Google returned nothing for is a gap rather than zero, since it
      # may not have been synced.
      def daily
        by_date = @stats.index_by(&:date)
        @daily ||= (period.from..period.to).map do |date|
          stat = by_date[date]
          next [date, nil, nil] unless stat

          day = stat.scores
          low = day.sum { |bucket| bucket["score"] < Stat::LOW_SCORE ? bucket["count"] : 0 }
          [date, low, count(day) - low]
        end
      end

      # Day for day so a month is read against the month before whatever
      # their lengths.
      def previous_daily
        return unless compared?

        by_date = @previous.index_by(&:date)
        (period.previous.from..period.previous.to).first(daily.size).map do |date|
          stat = by_date[date]
          count(stat.scores) if stat
        end
      end

      # Nil where that day wasn't synced, since it would read as a jump from
      # zero.
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

      # A day without challenges stays a gap rather than zero, as in the
      # current period.
      def previous_daily_challenges
        return unless compared?

        by_date = @previous.index_by(&:date)
        (period.previous.from..period.previous.to).first(period.days).map do |date|
          challenges = by_date[date]&.challenges
          challenges.presence && %w[no_challenge passed failed].sum { |name| challenges[name].to_i }
        end
      end

      # Of the challenges actually solved or failed, since one never shown
      # says nothing about who could solve it.
      def challenge_pass_rate(stats = @stats)
        passed = stats.sum { |stat| stat.challenges["passed"].to_i }
        failed = stats.sum { |stat| stat.challenges["failed"].to_i }
        passed.fdiv(passed + failed) if (passed + failed).positive?
      end

      def previous_challenge_pass_rate
        challenge_pass_rate(@previous) if compared?
      end

      def histogram
        counts = Hash.new(0)
        @stats.each { |stat| stat.scores.each { |bucket| counts[bucket["score"].to_f.round(1)] += bucket["count"].to_i } }
        Summary::BUCKETS.to_h { |score| [score, counts[score]] }
      end

      # Bucket for bucket, so a bar is read against the same score a period
      # earlier; nil where the period compared with has no stats at all.
      def previous_histogram
        return unless compared? && @previous.any?

        counts = Hash.new(0)
        @previous.each { |stat| stat.scores.each { |bucket| counts[bucket["score"].to_f.round(1)] += bucket["count"].to_i } }
        Summary::BUCKETS.map { |score| counts[score] }
      end

      # The total covers all actions so a share is of every one of them
      # rather than of the top few.
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
