# encoding: UTF-8

module Google
  module Analytics
    # In the background, so a feed sync doesn't wait on GA's API.
    class AnnotationJob < ApplicationJob
      queue_as :default

      def perform(request_id: nil)
        result = SyncRequest.track("analytics_annotations", request_id: request_id) { AnnotationService.call }
        Rails.logger.info("Analytics annotations: #{result.summary}")
        result.errors.each { |error| Rails.logger.warn("Analytics annotations: #{error}") }
      end
    end
  end
end
