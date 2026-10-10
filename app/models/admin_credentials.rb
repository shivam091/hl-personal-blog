# encoding: UTF-8

# The admin is a single person, so the login lives in the encrypted Rails
# credentials rather than a users collection, and an unset pair locks
# everyone out.
module AdminCredentials
  class << self
    def configured?
      username.present? && password.present?
    end

    # Constant-time so response timing can't reveal which part was wrong or
    # how much of it matched.
    def valid?(given_username, given_password)
      return false unless configured?

      username_matches = ActiveSupport::SecurityUtils.secure_compare(given_username.to_s, username)
      password_matches = ActiveSupport::SecurityUtils.secure_compare(given_password.to_s, password)
      username_matches & password_matches
    end

    # Lets a credential change sign out existing sessions without ever
    # putting the password in the session cookie.
    def fingerprint
      OpenSSL::HMAC.hexdigest("SHA256", Rails.application.secret_key_base, "#{username}\0#{password}")
    end

    def username
      login[:username].to_s
    end

    private

    def password
      login[:password].to_s
    end

    def login
      Rails.application.credentials.admin || {}
    end
  end
end
