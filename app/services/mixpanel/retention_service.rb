# encoding: UTF-8

module Mixpanel
  # New readers by the week they first came, and how many came back in each
  # week after, from Mixpanel's Query API.
  class RetentionService
    WEEKS = 8
    EVENT = "$mp_web_page_view"
    PLAN_RESTRICTED = 402

    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(client: Client.new, result: SyncResult.empty, today: Date.current)
      @client = client
      @result = result
      @today = today
    end

    def call
      return @result.tap { @result.errors << Client::NOT_CONFIGURED } unless @client.configured?

      reply = @client.query("retention",
        from_date: (@today - (WEEKS * 7 - 1)).iso8601, to_date: @today.iso8601, retention_type: "birth",
        born_event: EVENT, event: EVENT, unit: "week", interval_count: WEEKS)
      reply.each do |date, cohort|
        next unless cohort.is_a?(Hash)

        record = RetentionCohort.find_or_initialize_by(cohort_date: Date.parse(date))
        record.assign_attributes(first: cohort["first"].to_i, counts: Array(cohort["counts"]).map(&:to_i))
        outcome = record.new_record? ? :created : (record.changed? ? :updated : :unchanged)
        record.save! unless outcome == :unchanged
        @result[outcome] += 1
      end
      @result
    rescue Client::Error => e
      # The Query API is a paid plan's, so on Free every run would otherwise
      # fail the whole sync over a card the plan can't fill.
      if e.status == PLAN_RESTRICTED
        Rails.logger.info("Mixpanel retention skipped: #{e.message}")
      else
        @result.errors << "Mixpanel retention: #{e.message}"
      end
      @result
    rescue Date::Error => e
      @result.errors << "Mixpanel retention: #{e.message}"
      @result
    end
  end
end
