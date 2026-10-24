# encoding: UTF-8

namespace :admin_mail do
  desc "Mail credentials mailer.notify_to each entry's report on its 7th and 30th day"
  task launch_reports: :environment do
    # Failing rather than skipping, so a missing address shows as a failed run.
    abort "No recipient configured (credentials mailer.notify_to)" if SyncMailer.notify_to.blank?

    puts "Launch reports sent: #{LaunchReportsJob.perform_now}"
  end

  desc "Mail credentials mailer.notify_to the dashboard's Needs attention items, if there are any"
  task attention: :environment do
    abort "No recipient configured (credentials mailer.notify_to)" if SyncMailer.notify_to.blank?

    anomalies = Anomalies.new
    next puts("Nothing needs attention") unless anomalies.any?

    message = AdminMailer.attention(anomalies).message
    puts "Sent to #{Array(message.to).join(", ")}: #{message.subject}"
  end
end
