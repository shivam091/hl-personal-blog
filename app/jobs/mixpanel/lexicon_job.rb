# encoding: UTF-8

module Mixpanel
  class LexiconJob < ApplicationJob
    queue_as :default

    def perform(request_id: nil)
      result = SyncRequest.track("mixpanel_lexicon", request_id: request_id) { LexiconService.call }
      Rails.logger.info("Mixpanel Lexicon: #{result.summary}")
      result.errors.each { |error| Rails.logger.warn("Mixpanel Lexicon: #{error}") }
    end
  end
end
