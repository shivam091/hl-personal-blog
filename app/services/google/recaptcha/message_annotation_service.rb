# encoding: UTF-8

module Google
  module Recaptcha
    # Exists so Google can tune the contact form's scores on whether what got
    # through was a real message or spam.
    class MessageAnnotationService
      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(review, client: ApiClient.new(scope: Verifier::SCOPE))
        @review = review
        @client = client
      end

      # Kept on the review rather than only logged, so the message says why
      # Google wasn't told.
      def call
        error = annotate
        @review.set(error ? {annotation_error: error} : {annotated_at: Time.current, annotation_error: nil})
        error
      end

      private

      def annotate
        name = @review.message&.recaptcha_assessment
        return "No reCAPTCHA assessment was kept with this message" if name.blank?
        return ApiClient::NOT_CONFIGURED unless @client.configured?

        verdict = MessageReview::VERDICTS.fetch(@review.verdict)
        # The name is a path ("projects/p/assessments/a"), so it isn't escaped.
        @client.post(format(AnnotationService::ANNOTATE_URL, name: name), {annotation: verdict[:annotation], reasons: verdict[:reasons]}.compact_blank)
        nil
      rescue ApiClient::Error => e
        "#{name}: #{e.message}"
      end
    end
  end
end
