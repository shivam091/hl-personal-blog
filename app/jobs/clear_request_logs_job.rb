# encoding: UTF-8

# Clearing a big range can take a while, so it runs in the background
# instead of holding up the admin's request. ISO date strings rather than
# Date objects, so the arguments survive any queue adapter.
class ClearRequestLogsJob < ApplicationJob
  queue_as :default

  def perform(from, to, local_only: false)
    clearance = RequestLogClearance.new(from: from, to: to, local_only: local_only)
    raise ArgumentError, clearance.errors.full_messages.to_sentence unless clearance.valid?

    # One deleteMany on the server: once sent, it finishes even if this
    # process is restarted midway, as can happen during a deploy.
    deleted = clearance.scope.delete_all
    Rails.logger.info("Cleared #{deleted} #{"local " if local_only}request logs from #{from} to #{to}")
  end
end
