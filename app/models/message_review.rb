# encoding: UTF-8

# The admin's call on a contact message, kept apart from the message because
# the frontend owns that collection. Sent on to reCAPTCHA, so Google learns
# from what got through its score and shouldn't have.
class MessageReview
  include Mongoid::Document
  include Mongoid::Timestamps

  # Google's own words for each verdict. Spam also names why, since an
  # annotation's reasons are what the model learns most from.
  VERDICTS = {
    "genuine" => {label: "Genuine", annotation: "LEGITIMATE", reasons: []},
    "spam" => {label: "Spam", annotation: "FRAUDULENT", reasons: %w[SOCIAL_SPAM]}
  }.freeze

  field :message_id, type: BSON::ObjectId
  field :verdict, type: String
  field :annotated_at, type: Time
  # Why the verdict wasn't sent on, so a message marked before the form kept
  # assessments doesn't read as reported.
  field :annotation_error, type: String

  index({message_id: 1}, {unique: true})

  validates :message_id, presence: true
  validates :verdict, inclusion: {in: VERDICTS.keys}

  class << self
    def for(messages)
      where(:message_id.in => messages.map(&:id)).index_by(&:message_id)
    end

    # Changing a verdict sends the new one, since Google goes by the latest
    # annotation of an assessment. In the background, so the click doesn't
    # wait on Google.
    def mark(message, verdict)
      review = find_or_initialize_by(message_id: message.id)
      review.assign_attributes(verdict: verdict, annotated_at: nil, annotation_error: nil)
      return review unless review.save

      Google::Recaptcha::AnnotateMessageJob.perform_later(review.id.to_s)
      review
    end
  end

  def message
    Message.where(id: message_id).first
  end

  def label
    VERDICTS.fetch(verdict)[:label]
  end

  def spam?
    verdict == "spam"
  end
end
