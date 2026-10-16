# encoding: UTF-8

# A job, so the request doesn't wait on one email per subscriber.
class NotifySubscribersJob < ApplicationJob
  queue_as :default

  # So a resend after a failed send doesn't email those it already reached.
  def perform(url, emails = nil)
    entry = FeedEntry.where(_id: url).first
    return unless entry

    sent = emails ? entry.resend_to(emails) : entry.notify_subscribers
    Rails.logger.info("Notified #{sent} subscribers about #{url}")
  end
end
