# encoding: UTF-8

module Mixpanel
  # Replaces each event's schema with the plan's rather than truncating the
  # dictionary, so what Mixpanel describes for its own events, or what was
  # added by hand in its UI for others, is kept.
  class LexiconService
    class << self
      def call(...)
        new(...).call
      end
    end

    def initialize(client: Client.new)
      @client = client
    end

    def call
      result = SyncResult.empty
      return result.tap { result.errors << Client::NOT_CONFIGURED } unless @client.configured?

      reply = @client.app_post("schemas", entries: TrackingPlan.entries, truncate: false)
      result.updated += reply.dig("results", "added").to_i
      result
    rescue Client::Error => e
      result.errors << "Mixpanel Lexicon: #{e.message}"
      result
    end
  end
end
