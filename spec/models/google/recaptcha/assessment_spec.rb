# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Recaptcha::Assessment, type: :model do
  include ActiveJob::TestHelper

  it "records the password outcome and annotates an Enterprise assessment in the background" do
    assessment = described_class.create!(name: "projects/123/assessments/abc")

    expect { assessment.record_password(false) }.to have_enqueued_job(
      Google::Recaptcha::AnnotateAssessmentJob
    ).with(assessment.id.to_s)
    expect(assessment.reload.password_outcome).to eq("INCORRECT_PASSWORD")
  end

  it "doesn't annotate a siteverify check, which Google keeps no record of" do
    assessment = described_class.create!

    expect { assessment.record_password(true) }.not_to have_enqueued_job
    expect(assessment.reload.password_outcome).to eq("CORRECT_PASSWORD")
  end

  it "accepts only outcomes Google understands" do
    expect(described_class.new(password_outcome: "MAYBE")).not_to be_valid
  end
end
