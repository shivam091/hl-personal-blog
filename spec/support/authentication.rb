# encoding: UTF-8

module AuthenticationHelpers
  ADMIN_USERNAME = "admin"
  ADMIN_PASSWORD = "correct horse battery staple"

  def sign_in(username: ADMIN_USERNAME, password: ADMIN_PASSWORD)
    post session_path, params: {username: username, password: password}
  end

  # Specs must not depend on whatever login the local credentials file holds.
  def stub_admin_credentials(username: ADMIN_USERNAME, password: ADMIN_PASSWORD)
    allow(Rails.application.credentials).to receive(:admin) { {username: username, password: password} }
  end
end

RSpec.configure do |config|
  config.include AuthenticationHelpers
  config.include ActiveSupport::Testing::TimeHelpers

  config.before do
    stub_admin_credentials
    # Off unless a spec turns it on, so a reCAPTCHA key in the local
    # credentials doesn't turn away the token-less test sign-in.
    allow(Rails.application.credentials).to receive(:recaptcha) { nil }
  end

  config.before(type: :request) do |example|
    sign_in unless example.metadata[:signed_out]
  end
end
