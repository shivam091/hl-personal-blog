# encoding: UTF-8

# Mails each entry's launch report on the day it turns each age, so how a
# new entry is doing arrives without anyone thinking to look.
class LaunchReportsJob < ApplicationJob
  queue_as :default

  # A run missed for a day or two (a failed workflow, say) still sends the
  # report late rather than never; entries older than this were published
  # before anyone could have been waiting on one.
  CATCH_UP_DAYS = 3

  # Every due report is tried even when one fails, so one broken entry
  # doesn't hold back the rest; the failure still fails the run.
  def perform(today: Date.current)
    failures = []
    sent = LaunchReport::AGES.sum do |age|
      due(age, today).count do |entry|
        next false unless LaunchReportDelivery.claim(entry.url, age)

        deliver(entry, age, today)
      rescue => e
        LaunchReportDelivery.release(entry.url, age)
        failures << "#{entry.url} (day #{age}): #{e.message}"
        false
      end
    end
    Rails.logger.info("Launch reports: #{sent} sent")
    raise "Launch reports failed: #{failures.join("; ")}" if failures.any?

    sent
  end

  private

  # Published on the day that makes it the age today, or within the days a
  # missed run could have left it waiting.
  def due(age, today)
    first = today - age - CATCH_UP_DAYS
    FeedEntry.where(published_at: first.in_time_zone.beginning_of_day..(today - age).in_time_zone.end_of_day).order(published_at: :asc)
  end

  def deliver(entry, age, today)
    AdminMailer.launch_report(LaunchReport.new(entry, age, today: today)).message
    LaunchReportDelivery.sent(entry.url, age)
    true
  end
end
