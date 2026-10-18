# encoding: UTF-8

require "csv"

module Google
  module Recaptcha
    # Copied from Google because it only shows recent weeks, too few to
    # judge whether the score threshold forms reject at is turning away
    # people or only bots.
    class Stat
      include Mongoid::Document
      include DailyStat

      # Lists rather than hashes keyed by score, since MongoDB treats the dot
      # in "0.9" as a path.
      field :scores, type: Array, default: []
      field :action_scores, type: Hash, default: {}
      # Only checkbox keys are challenged; empty for score-only (v3) keys.
      field :challenges, type: Hash, default: {}

      # Highest first, as Google lists them, so exports read like its console.
      SCORE_BUCKETS = (0..10).map { |tenth| tenth / 10.0 }.reverse.freeze
      # Google's suggested starting threshold, so the share below it shows
      # how many requests a typical setup would turn away.
      LOW_SCORE = 0.5
      CHALLENGES = %w[page_loads no_challenge passed failed].freeze

      key_fields

      index({date: 1}, {unique: true})

      def requests
        scores.sum { |bucket| bucket["count"] }
      end

      def low_score_requests
        scores.sum { |bucket| bucket["score"] < LOW_SCORE ? bucket["count"] : 0 }
      end

      def average_score
        return if requests.zero?

        scores.sum { |bucket| bucket["score"] * bucket["count"] }.fdiv(requests)
      end

      class << self
        def to_csv(stats)
          CSV.generate do |csv|
            csv << ["Date", "Requests", *SCORE_BUCKETS.map { |score| "Score #{score}" }, "Average score",
              *CHALLENGES.map { |name| name.humanize }]
            stats.each do |stat|
              csv << [stat.date.iso8601, stat.requests, *bucket_counts(stat.scores), stat.average_score&.round(3),
                *CHALLENGES.map { |name| stat.challenges[name] }]
            end
          end
        end

        # A row per day and action, since each form is scored on its own.
        def actions_csv(stats)
          CSV.generate do |csv|
            csv << ["Date", "Action", "Requests", *SCORE_BUCKETS.map { |score| "Score #{score}" }]
            stats.each do |stat|
              stat.action_scores.sort.each do |action, buckets|
                csv << [stat.date.iso8601, action, buckets.sum { |bucket| bucket["count"] }, *bucket_counts(buckets)]
              end
            end
          end
        end

        private

        def bucket_counts(buckets)
          counts = buckets.to_h { |bucket| [bucket["score"], bucket["count"]] }
          SCORE_BUCKETS.map { |score| counts.fetch(score, 0) }
        end
      end
    end
  end
end
