# encoding: UTF-8

module Webhooks
  class BrevoController < ApplicationController
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
      expected = Rails.application.credentials.dig(:brevo, :webhook_token).to_s
      return if expected.present? && ActiveSupport::SecurityUtils.secure_compare(given_token, expected)

      head :unauthorized
    end

    # Brevo's token authentication doesn't document the header's form, so the
    # token is taken whether or not a scheme word precedes it; the query
    # parameter is kept for a webhook set up without authentication.
    def given_token
      header = request.authorization.to_s.strip.split(/\s+/).last
      header.presence || params[:token].to_s
    end

    def payload
      body = JSON.parse(request.raw_post)
      events = body.is_a?(Array) ? body : [body]
      events if events.all?(Hash)
    rescue JSON::ParserError
      # A malformed body is answered as a bad request rather than raising.
      nil
    end
  end
end
