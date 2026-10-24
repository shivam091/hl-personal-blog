# encoding: UTF-8

# At /rails/mailers/sync_mailer, from the development database's own syncs and snapshots.
class SyncMailerPreview < ActionMailer::Preview
  include UndeliveredPreview

  def daily_digest
    undelivered { SyncMailer.daily_digest(SyncDigest.new) }
  end
end
