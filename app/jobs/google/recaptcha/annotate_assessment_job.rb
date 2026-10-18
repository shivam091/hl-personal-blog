# encoding: UTF-8

module Google
  module Recaptcha
    # In the background, so signing in isn't kept waiting on Google.
    class AnnotateAssessmentJob < ApplicationJob
      queue_as :default

      def perform(assessment_id)
        assessment = Assessment.where(id: assessment_id).first
        return unless assessment

        error = AnnotationService.call(assessment)
        Rails.logger.warn("reCAPTCHA annotation: #{error}") if error
      end
    end
  end
end
