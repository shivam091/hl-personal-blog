# encoding: UTF-8

# The only way into the admin, so it's the one controller reachable while
# signed out, and is rate limited against password guessing.
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  # One name for the token's action, since the verifier refuses a token
  # requested for any other.
  RECAPTCHA_ACTION = "login"

  rate_limit to: 10,
             within: 3.minutes,
             only: :create,
             with: -> { redirect_to new_session_path, alert: "Too many login attempts. Try again in a few minutes." }

  def new
    redirect_to root_path if authenticated?
  end

  # reCAPTCHA first, so a bot learns nothing about the password.
  def create
    verdict = Google::Recaptcha::Verifier.check(
      params[:recaptcha_token],
      action: RECAPTCHA_ACTION,
      remote_ip: request.remote_ip,
      user_agent: request.user_agent
    )
    unless verdict.human?
      flash.now[:alert] = "Couldn't confirm you're not a bot. Please try again."
      return render :new, status: :unprocessable_content
    end

    password_correct = AdminCredentials.valid?(params[:username], params[:password])
    verdict.assessment&.record_password(password_correct)

    if password_correct
      redirect_to start_authenticated_session || root_path
    else
      flash.now[:alert] = if AdminCredentials.configured?
        "Incorrect username or password."
      else
        "Login isn't set up: set ADMIN_USERNAME and ADMIN_PASSWORD."
      end
      render :new, status: :unprocessable_content
    end
  end

  def destroy
    end_authenticated_session
    redirect_to new_session_path, notice: "Signed out."
  end
end
