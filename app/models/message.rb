# encoding: UTF-8

require "csv"

# Read-only because the frontend owns the collection.
class Message
  include Mongoid::Document
  include ReadOnly

  CSV_HEADERS = ["Name", "Email", "Message", "reCAPTCHA score", "Country", "Sent"].freeze

  field :name, type: String
  field :email, type: String
  field :message, type: String
  # The form already rejects anything under 0.5, so a stored score only
  # tells likely-human from borderline.
  field :recaptchaScore, type: Float, as: :recaptcha_score
  # reCAPTCHA Enterprise's name for the check ("projects/p/assessments/a"),
  # so a verdict on the message can be sent back to Google. Absent on
  # messages checked through the legacy endpoint, which keeps none.
  field :recaptchaAssessment, type: String, as: :recaptcha_assessment
  field :country, type: String
  field :createdAt, type: Time, as: :created_at

  # People type their address in different cases on different forms.
  scope :with_email, ->(email) { where(email: /\A#{Regexp.escape(email.to_s)}\z/i) }

  def subscriber
    NewsletterSubscriber.with_email(email).first
  end

  def other_messages
    Message.with_email(email).where(:_id.ne => id).order(created_at: :desc)
  end

  def review
    MessageReview.where(message_id: id).first
  end

  def to_s
    "#{name} <#{email}>"
  end

  class << self
    # So a copy of the messages exists outside the frontend's collection.
    def to_csv(messages = order(created_at: :desc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        messages.each do |message|
          csv << [
            message.name,
            message.email,
            message.message,
            message.recaptcha_score,
            message.country,
            message.created_at&.utc&.iso8601(3)
          ]
        end
      end
    end
  end
end
