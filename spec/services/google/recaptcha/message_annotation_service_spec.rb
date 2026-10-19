# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::MessageAnnotationService do
  let(:url) { "https://recaptchaenterprise.googleapis.com/v1/projects/123/assessments/abc:annotate" }

  def review(verdict, assessment: "projects/123/assessments/abc")
    id = Message.collection.insert_one("name" => "Ada", "email" => "ada@domain.com", "message" => "Hi", "recaptchaAssessment" => assessment).inserted_id
    MessageReview.create!(message_id: id, verdict: verdict)
  end

  it "reports spam as fraudulent social spam and a genuine message as legitimate, noting when Google took it" do
    sent = []
    google_stubs.post(url) { |env| sent << JSON.parse(env.body); [200, {}, "{}"] }
    spam = review("spam")

    expect(described_class.call(spam, client: google_client)).to be_nil
    expect(spam.reload.annotated_at).to be_present

    Message.delete_all
    MessageReview.delete_all
    described_class.call(review("genuine"), client: google_client)
    expect(sent).to eq([{"annotation" => "FRAUDULENT", "reasons" => ["SOCIAL_SPAM"]}, {"annotation" => "LEGITIMATE"}])
  end

  it "keeps Google's error on the review instead of raising" do
    google_stubs.post(url) { [403, {}, {error: {message: "Permission denied"}}.to_json] }
    spam = review("spam")

    expect(described_class.call(spam, client: google_client)).to eq("projects/123/assessments/abc: Permission denied")
    expect(spam.reload).to have_attributes(annotated_at: nil, annotation_error: "projects/123/assessments/abc: Permission denied")
  end

  it "says why a message checked without an assessment can't be reported" do
    spam = review("spam", assessment: nil)

    expect(described_class.call(spam, client: google_client)).to eq("No reCAPTCHA assessment was kept with this message")
  end
end
