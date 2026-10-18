# encoding: UTF-8

require "rails_helper"

RSpec.describe "Sessions", type: :request, signed_out: true do
  it "sends signed-out requests to the login page, with no nav" do
    [crawled_pages_path, crawled_pages_path(format: :csv), new_crawled_page_path].each do |path|
      get path
      expect(response).to redirect_to(new_session_path), path
    end

    get new_session_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Sign in", "This application is for authorised users only.")
    expect(response.body).not_to include("Crawled pages", "Sign out")
  end

  it "blocks writes too" do
    post crawled_pages_path, params: {crawled_page: {url: "https://example.com/a"}}

    expect(response).to redirect_to(new_session_path)
    expect(CrawledPage.count).to eq(0)
  end

  it "keeps the health check public" do
    get rails_health_check_path
    expect(response).to have_http_status(:ok)
  end

  it "logs in with the credentials from Rails credentials" do
    sign_in

    expect(response).to redirect_to(root_path)
    follow_redirect!
    expect(response.body).to include("Dashboard", "Sign out")
  end

  it "returns to the page first asked for" do
    get crawled_pages_path(q: "css")
    sign_in

    expect(response).to redirect_to(crawled_pages_path(q: "css"))
  end

  it "rejects a wrong username or password" do
    [["admin", "wrong"], ["someone", AuthenticationHelpers::ADMIN_PASSWORD], ["", ""]].each do |username, password|
      sign_in(username: username, password: password)

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Incorrect username or password.")
    end

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "lets nobody in while the credentials aren't set, not even with blank ones" do
    stub_admin_credentials(username: "", password: "")

    sign_in(username: "", password: "")

    expect(response).to have_http_status(:unprocessable_content)
    expect(response.body).to include("Login isn&#39;t set up")
  end

  it "signs out" do
    sign_in
    delete session_path

    expect(response).to redirect_to(new_session_path)
    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "ends sessions when the password changes" do
    sign_in
    stub_admin_credentials(password: "a new password")

    get root_path
    expect(response).to redirect_to(new_session_path)
  end

  it "ends sessions after #{Authentication::SESSION_TTL.inspect}" do
    sign_in

    travel(Authentication::SESSION_TTL - 1.minute) { get root_path }
    expect(response).to have_http_status(:ok)

    travel(Authentication::SESSION_TTL + 1.minute) { get root_path }
    expect(response).to redirect_to(new_session_path)
  end

  it "skips the login page when already signed in" do
    sign_in
    get new_session_path

    expect(response).to redirect_to(root_path)
  end

  context "with reCAPTCHA keys set" do
    before do
      allow(Rails.application.credentials).to receive(:recaptcha) { {site_key: "site-key", secret_key: "secret"} }
    end

    it "loads reCAPTCHA on the login form" do
      get new_session_path

      expect(response.body).to include("https://www.google.com/recaptcha/api.js?render=site-key", 'data-controller="recaptcha"', 'name="recaptcha_token"')
    end

    it "checks the token before the password, then tells reCAPTCHA whether the password was right" do
      assessment = Google::Recaptcha::Assessment.create!
      allow(Google::Recaptcha::Verifier).to receive(:check) { Google::Recaptcha::Verifier::Verdict.new(true, assessment) }

      post session_path, params: {
        username: AuthenticationHelpers::ADMIN_USERNAME,
        password: AuthenticationHelpers::ADMIN_PASSWORD,
        recaptcha_token: "token"
      }

      expect(response).to redirect_to(root_path)
      expect(Google::Recaptcha::Verifier).to have_received(:check).with("token", action: "login", remote_ip: "127.0.0.1", user_agent: nil)
      expect(assessment.reload.password_outcome).to eq("CORRECT_PASSWORD")

      delete session_path
      assessment = Google::Recaptcha::Assessment.create!
      allow(Google::Recaptcha::Verifier).to receive(:check) do
        Google::Recaptcha::Verifier::Verdict.new(true, assessment)
      end
      sign_in(password: "wrong")
      expect(assessment.reload.password_outcome).to eq("INCORRECT_PASSWORD")
    end

    it "turns away a failed check even with the right password" do
      allow(Google::Recaptcha::Verifier).to receive(:check) do
        Google::Recaptcha::Verifier::Verdict.new(false, nil)
      end

      sign_in

      expect(response).to have_http_status(:unprocessable_content)
      expect(response.body).to include("Couldn&#39;t confirm you&#39;re not a bot.")
      get root_path
      expect(response).to redirect_to(new_session_path)
    end
  end

  it "leaves reCAPTCHA off the login form while its keys aren't set" do
    allow(Rails.application.credentials).to receive(:recaptcha) { nil }
    get new_session_path

    expect(response.body).not_to include("recaptcha/api.js", 'data-controller="recaptcha"', "recaptcha_token")
  end
end
