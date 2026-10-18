# encoding: UTF-8

module Google
  module Recaptcha
    class MetricsSyncJob < ApplicationJob
      queue_as :default

      def perform(request_id: nil)
        result = SyncRequest.track("recaptcha_metrics", request_id: request_id) { MetricsSyncService.call }
        Rails.logger.info("reCAPTCHA metrics sync: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("reCAPTCHA metrics sync: #{error}") }
      end
    end
  end
end
