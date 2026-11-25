# encoding: UTF-8

module Mixpanel
  class AnnotationJob < ApplicationJob
    queue_as :default

    def perform(request_id: nil)
      result = SyncRequest.track("mixpanel_annotations", request_id: request_id) { AnnotationService.call }
      Rails.logger.info("Mixpanel annotations: #{result.summary}")
      result.errors.each { |error| Rails.logger.warn("Mixpanel annotations: #{error}") }
    end
  end
end
