# encoding: UTF-8

class SyncMailer < ApplicationMailer
  helper SyncRequestsHelper

  class << self
    # From credentials, so the address stays out of the code like the sender's.
    def notify_to
      Rails.application.credentials.dig(:mailer, :notify_to)
    end
  end

  def daily_digest(digest = SyncDigest.new)
    deliver_with_logging(__method__) do
      @digest = digest
      mail(to: self.class.notify_to, subject: "Sync digest: #{digest.summary}")
    end
  end
end
