# encoding: UTF-8

require "csv"

module Google
  module Recaptcha
    # Kept per login attempt because Google's daily metrics only count scores:
    # they can't say why a given attempt was turned away, or whether
    # turned-away attempts came with the right password.
    class Assessment
      include Mongoid::Document
      include Mongoid::Timestamps

      # Limited to what Google accepts as feedback, so a bad value is caught
      # here rather than refused by Google later.
      PASSWORD_OUTCOMES = %w[CORRECT_PASSWORD INCORRECT_PASSWORD].freeze

      # Blank when checked through the legacy siteverify endpoint, which keeps
      # no id, so no feedback can be sent on those.
      field :name, type: String
      field :action, type: String
      field :expected_action, type: String
      field :score, type: Float
      field :reasons, type: Array, default: []
      field :valid_token, type: Boolean
      field :invalid_reason, type: String
      field :hostname, type: String
      field :token_created_at, type: Time
      field :remote_ip, type: String
      field :user_agent, type: String
      field :accepted, type: Boolean
      field :password_outcome, type: String
      field :annotated_at, type: Time

      # Sorts carry an _id tiebreaker, which an index without it can't serve.
      index({created_at: -1, _id: 1})
      index({accepted: 1})

      validates :password_outcome, inclusion: {in: PASSWORD_OUTCOMES}, allow_nil: true

      class << self
        def to_csv(assessments)
          CSV.generate do |csv|
            csv << [
              "Time", "Action", "Expected action", "Score", "Accepted", "Invalid reason", "Reasons",
              "Password outcome", "Annotated", "IP", "User agent", "Hostname", "Assessment"
            ]
            assessments.each do |assessment|
              csv << [
                assessment.created_at&.utc&.iso8601,
                assessment.action,
                assessment.expected_action,
                assessment.score,
                assessment.accepted ? "Yes" : "No",
                assessment.invalid_reason,
                assessment.reasons.join(" "),
                assessment.password_outcome,
                assessment.annotated_at&.utc&.iso8601,
                assessment.remote_ip,
                assessment.user_agent,
                assessment.hostname,
                assessment.name
              ]
            end
          end
        end
      end

      def to_s
        "#{action.presence || "Unknown action"} check from #{remote_ip.presence || "an unknown IP"}"
      end

      # Google tunes this site's scores on feedback, and a password guess is
      # the clearest sign it gets of who was a bot. Sent in the background so
      # the login doesn't wait on it.
      def record_password(correct)
        return unless persisted?

        set(password_outcome: correct ? "CORRECT_PASSWORD" : "INCORRECT_PASSWORD")
        Google::Recaptcha::AnnotateAssessmentJob.perform_later(id.to_s) if name.present?
      end
    end
  end
end
