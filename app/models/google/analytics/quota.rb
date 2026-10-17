# encoding: UTF-8

module Google
  module Analytics
    # What's left of GA's Data API quota after the latest request of each
    # kind, so a sync about to fail on quota is seen before it does. GA
    # counts reports, realtime reports and funnels against separate quotas.
    class Quota
      include Mongoid::Document
      include Mongoid::Timestamps

      CATEGORIES = {"core" => "Reports", "realtime" => "Realtime", "funnel" => "Funnels"}.freeze
      # GA's names, in the order its quota docs list them, with a standard
      # (not 360) property's limits, since the response only says what's
      # left. https://developers.google.com/analytics/devguides/reporting/data/v1/quotas
      LIMITS = {
        "tokensPerDay" => ["Tokens per day", 200_000],
        "tokensPerHour" => ["Tokens per hour", 40_000],
        "tokensPerProjectPerHour" => ["Tokens per project per hour", 14_000],
        "concurrentRequests" => ["Concurrent requests", 10],
        "serverErrorsPerProjectPerHour" => ["Server errors per project per hour", 10],
        "potentiallyThresholdedRequestsPerHour" => ["Possibly thresholded requests per hour", 120]
      }.freeze
      # Under this share of a limit left, the next sync may well be refused.
      LOW_SHARE = 0.1

      Usage = Struct.new(:key, :label, :limit, :consumed, :remaining, keyword_init: true) do
        def remaining_share
          remaining.fdiv(limit) if remaining && limit.positive?
        end

        def low?
          remaining_share && remaining_share < LOW_SHARE
        end
      end

      field :category, type: String
      field :recorded_at, type: Time
      # {"tokensPerDay" => {"consumed" => 12, "remaining" => 199_870}, ...}:
      # what the latest request cost, and what was left after it.
      field :quota, type: Hash, default: {}

      index({category: 1}, {unique: true})

      validates :category, inclusion: {in: CATEGORIES.keys}

      class << self
        # Never raises, since a quota that can't be stored mustn't fail the
        # report it came with.
        def record(category, response)
          property_quota = response.is_a?(Hash) ? response["propertyQuota"] : nil
          return if property_quota.blank?

          where(category: category).find_one_and_update(
            {
              "$set" => {
                quota: property_quota.slice(*LIMITS.keys),
                recorded_at: Time.current,
                updated_at: Time.current
              },
             "$setOnInsert" => {created_at: Time.current}
            },
            upsert: true
          )
        rescue Mongo::Error => e
          Rails.logger.warn("Analytics quota not recorded: #{e.message}")
        end
      end

      def usages
        LIMITS.map do |key, (label, limit)|
          values = quota.fetch(key, {})
          Usage.new(
            key: key,
            label: label,
            limit: limit,
            consumed: values["consumed"]&.to_i,
            remaining: values["remaining"]&.to_i
          )
        end
      end

      def low?
        usages.any?(&:low?)
      end
    end
  end
end
