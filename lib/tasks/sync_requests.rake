# encoding: UTF-8

namespace :sync_requests do
  desc "Mail a digest of the last 24 hours' syncs to credentials mailer.notify_to"
  task digest: :environment do
    # Failing rather than skipping, so a missing address shows as a failed run.
    if SyncMailer.notify_to.blank?
      abort "No digest recipient configured (credentials mailer.notify_to)"
    end

    message = SyncMailer.daily_digest.message
    puts "Sync digest sent to #{Array(message.to).join(", ")}: #{message.subject}"
  end
end
