# encoding: UTF-8

module Google
  module Recaptcha
    # In the background, so marking a message doesn't wait on Google.
    class AnnotateMessageJob < ApplicationJob
      queue_as :default

      def perform(review_id)
        review = MessageReview.where(id: review_id).first
        return unless review

        error = MessageAnnotationService.call(review)
        Rails.logger.warn("reCAPTCHA message annotation: #{error}") if error
      end
    end
  end
end
