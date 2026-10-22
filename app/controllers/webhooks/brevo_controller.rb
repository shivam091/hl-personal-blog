# encoding: UTF-8

module Webhooks
  # Exists so whether new-entry mails arrive, and are opened and clicked,
  # is known here rather than only in Brevo's short-lived logs.
  class BrevoController < ApplicationController
    TOKEN_ENV = "BREVO_WEBHOOK_TOKEN"

    # Brevo posts without a session or a form's token; the shared secret in
    # its URL is what keeps anyone else from posting events.
    allow_unauthenticated_access
    skip_forgery_protection
    before_action :require_token

    # Anything but a refusal tells Brevo the event arrived, so an event
    # stored already, or one not wanted, is still a success; otherwise
    # Brevo would keep retrying it.
    def create
      events = payload
      return head(:bad_request) if events.nil?

      events.each { |event| NewsletterEmailEvent.record(event) }
      head :ok
    end

    private

    # Unset refuses everything, so a missing setting can't leave the
    # endpoint open. Compared in constant time, so the secret can't be
    # guessed a character at a time.
    def require_token
      expected = ENV[TOKEN_ENV].to_s
      return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(params[:token].to_s, expected)

      head :unauthorized
    end

    # One event a request, or a list when Brevo batches them.
    def payload
      body = JSON.parse(request.raw_post)
      events = body.is_a?(Array) ? body : [body]
      events if events.all?(Hash)
    rescue JSON::ParserError
      nil
    end
  end
end
