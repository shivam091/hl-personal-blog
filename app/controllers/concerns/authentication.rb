# encoding: UTF-8

# Makes signing in the default for every action, so a new page can't be
# left public by forgetting a filter; opting out has to be explicit.
module Authentication
  extend ActiveSupport::Concern

  # Caps how long a stolen or forgotten session stays useful, however
  # active it is.
  SESSION_TTL = 12.hours

  included do
    before_action :require_authentication
    helper_method :authenticated?
  end

  class_methods do
    def allow_unauthenticated_access(**options)
      skip_before_action :require_authentication, **options
    end
  end

  private

  # Checked against the current credentials, so changing them signs every
  # existing session out.
  def authenticated?
    return @authenticated if defined?(@authenticated)

    fingerprint = session[:admin_fingerprint]
    @authenticated = AdminCredentials.configured? && fingerprint.is_a?(String) &&
      ActiveSupport::SecurityUtils.secure_compare(fingerprint, AdminCredentials.fingerprint) &&
      session[:signed_in_at].to_i > SESSION_TTL.ago.to_i
    record_admin_on_request_log if @authenticated
    @authenticated
  end

  # So request logs can say which admin made each request.
  def record_admin_on_request_log
    request.env[RequestLogger::USER_ENV_KEY] = AdminCredentials.username
  end

  def require_authentication
    return if authenticated?

    # Only pages are worth returning to after login; replaying a form
    # submission would not be. HEAD counts because Rails routes it like GET.
    session[:return_to] = request.fullpath if request.get? || request.head?
    redirect_to new_session_path
  end

  # A fresh session id so a planted one can't be fixated; the saved path so
  # the admin lands back where they were headed.
  def start_authenticated_session
    return_to = session[:return_to]
    reset_session
    session[:admin_fingerprint] = AdminCredentials.fingerprint
    session[:signed_in_at] = Time.current.to_i
    record_admin_on_request_log
    # Local paths only, so login can't become an open redirect.
    return_to if return_to.is_a?(String) && return_to.start_with?("/") && !return_to.start_with?("//")
  end

  def end_authenticated_session
    reset_session
    @authenticated = false
  end
end
