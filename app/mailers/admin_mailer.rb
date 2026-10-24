# encoding: UTF-8

# Mail for the admin about the blog itself, apart from the sync digest, so
# each has a subject of its own to filter or be alerted by.
class AdminMailer < ApplicationMailer
  helper DashboardHelper

  def launch_report(report)
    deliver_with_logging(__method__) do
      @report = report
      mail(to: SyncMailer.notify_to, subject: "Day #{report.age}: #{report.entry.name} is #{report.summary}")
    end
  end

  # Only for days with something on it, so the mail arriving is itself
  # the alert.
  def attention(anomalies = Anomalies.new)
    deliver_with_logging(__method__) do
      @flags = anomalies.flags
      subject = @flags.one? ? @flags.first.title : "#{@flags.size} things need attention"
      mail(to: SyncMailer.notify_to, subject: "Needs attention: #{subject}")
    end
  end
end
