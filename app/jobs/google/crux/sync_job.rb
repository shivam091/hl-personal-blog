# encoding: UTF-8

module Google
  module Crux
    class SyncJob < ApplicationJob
      queue_as :default

      def perform(request_id: nil)
        result = SyncRequest.track("crux", request_id: request_id) { SyncService.call }
        Rails.logger.info("CrUX sync: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("CrUX sync: #{error}") }
      end
    end
  end
end
