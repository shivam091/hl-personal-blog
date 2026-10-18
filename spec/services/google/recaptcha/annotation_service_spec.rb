# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::AnnotationService do
  let(:url) { "https://recaptchaenterprise.googleapis.com/v1/projects/123/assessments/abc:annotate" }
  let(:assessment) do
    Google::Recaptcha::Assessment.create!(
      name: "projects/123/assessments/abc",
      password_outcome: "INCORRECT_PASSWORD"
    )
  end

  it "sends the password outcome and notes when Google took it" do
    sent = nil
    google_stubs.post(url) { |env| sent = JSON.parse(env.body); [200, {}, "{}"] }

    expect(described_class.call(assessment, client: google_client)).to be_nil
    expect(sent).to eq("reasons" => ["INCORRECT_PASSWORD"])
    expect(assessment.reload.annotated_at).to be_present
  end

  it "returns Google's error instead of raising" do
    google_stubs.post(url) { [403, {}, {error: {message: "Permission denied"}}.to_json] }

    expect(described_class.call(assessment, client: google_client)).to eq("projects/123/assessments/abc: Permission denied")
    expect(assessment.reload.annotated_at).to be_nil
  end

  it "skips a check that has nothing to annotate" do
    siteverify = Google::Recaptcha::Assessment.create!(password_outcome: "CORRECT_PASSWORD")

    expect(described_class.call(siteverify, client: google_client)).to include("no Enterprise assessment")
  end
end
