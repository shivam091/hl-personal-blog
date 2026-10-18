# encoding: UTF-8

module Google
  module Recaptcha
    # Exists so Google can tune this site's scores on whether the password
    # that followed an assessment was right.
    class AnnotationService
      ANNOTATE_URL = "https://recaptchaenterprise.googleapis.com/v1/%{name}:annotate"

      class << self
        def call(...)
          new(...).call
        end
      end

      def initialize(assessment, client: ApiClient.new(scope: Verifier::SCOPE))
        @assessment = assessment
        @client = client
      end

      def call
        return "#{@assessment.id} has no Enterprise assessment to annotate" if @assessment.name.blank?
        return "#{@assessment.id} has no password outcome yet" if @assessment.password_outcome.blank?
        return ApiClient::NOT_CONFIGURED unless @client.configured?

        # The name is a path ("projects/p/assessments/a"), so it isn't escaped.
        @client.post(format(ANNOTATE_URL, name: @assessment.name), {reasons: [@assessment.password_outcome]})
        @assessment.set(annotated_at: Time.current)
        nil
      rescue ApiClient::Error => e
        "#{@assessment.name}: #{e.message}"
      end
    end
  end
end
