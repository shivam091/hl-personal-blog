# encoding: UTF-8

# The only way into the admin, so it's the one controller reachable while
# signed out, and is rate limited against password guessing.
class SessionsController < ApplicationController
  allow_unauthenticated_access only: %i[new create]

  rate_limit to: 10,
             within: 3.minutes,
             only: :create,
             with: -> { redirect_to new_session_path, alert: "Too many login attempts. Try again in a few minutes." }

  def new
    redirect_to root_path if authenticated?
  end

  def create
    password_correct = AdminCredentials.valid?(params[:username], params[:password])

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
