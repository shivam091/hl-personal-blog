# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::AnnotateAssessmentJob do
  it "annotates the assessment" do
    assessment = Google::Recaptcha::Assessment.create!(
      name: "projects/123/assessments/abc",
      password_outcome: "CORRECT_PASSWORD"
    )
    allow(Google::Recaptcha::AnnotationService).to receive(:call) { nil }

    described_class.perform_now(assessment.id.to_s)

    expect(Google::Recaptcha::AnnotationService).to have_received(:call).with(assessment)
  end

  it "does nothing for an assessment that's gone" do
    allow(Google::Recaptcha::AnnotationService).to receive(:call)

    described_class.perform_now(BSON::ObjectId.new.to_s)

    expect(Google::Recaptcha::AnnotationService).not_to have_received(:call)
  end
end
