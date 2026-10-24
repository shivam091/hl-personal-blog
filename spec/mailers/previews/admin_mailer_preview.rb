# encoding: UTF-8

# At /rails/mailers/admin_mailer, from the development database's own entries.
class AdminMailerPreview < ActionMailer::Preview
  include UndeliveredPreview

  # The latest entry a week old, as the launch job would pick it on its seventh day.
  def launch_report
    undelivered { AdminMailer.launch_report(week_old_report) }
  end

  # The same with GA's share filled in, since a young entry rarely has the views to work one out.
  def launch_report_with_ga_share
    report = week_old_report
    report.define_singleton_method(:ga_share) { 0.42 }
    undelivered { AdminMailer.launch_report(report) }
  end

  private

  def week_old_report
    LaunchReport.new(FeedEntry.where(:published_at.lte => 7.days.ago).order(published_at: :desc).first, 7)
  end
end
