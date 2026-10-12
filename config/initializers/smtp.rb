# encoding: UTF-8

# SMTP rather than Brevo's API, so Action Mailer needs no gem; its key is
# separate from the API key the frontend uses. Wherever the credentials
# exist, so mail can be tried locally too, but never in tests, so no spec
# mails a real inbox.
brevo = Rails.application.credentials.brevo || {}

if brevo[:smtp_login].present? && brevo[:smtp_key].present? && !Rails.env.test?
  Rails.application.config.action_mailer.delivery_method = :smtp
  Rails.application.config.action_mailer.raise_delivery_errors = true
  Rails.application.config.action_mailer.smtp_settings = {
    address: "smtp-relay.brevo.com",
    # Brevo's alternative to 587, since Render's free plan blocks the usual
    # SMTP ports (25, 465 and 587), timing every send out.
    port: 2525,
    user_name: brevo[:smtp_login],
    password: brevo[:smtp_key],
    authentication: :login,
    enable_starttls_auto: true
  }
end
