# encoding: UTF-8

require "rails_helper"

RSpec.describe FeedEntry, "notifying subscribers", type: :model do
  def create_entry(url = "https://blog.example.com/posts/new")
    FeedEntry.create!(url: url, name: "Hello", type: "post", published_at: Time.current, last_modified_at: Time.current)
  end

  # Sending needs a sender and an unsubscribe secret, which CI's credentials
  # lack.
  before do
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :from) { "Blog <blog@domain.com>" }
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :unsubscribe_secret) { "test-secret" }
    ActionMailer::Base.deliveries.clear
    NewsletterSubscriber.create!(email: "ada@domain.com", subscribed_at: 1.month.ago)
    NewsletterSubscriber.create!(email: "grace@domain.com", subscribed_at: 1.week.ago)
  end

  it "mails no one when an entry is created" do
    create_entry

    expect(ActionMailer::Base.deliveries).to be_empty
  end

  it "can be claimed once, on the day it was published" do
    entry = create_entry

    expect(entry.claim_notification!).to be_truthy
    expect(entry.reload.notified_at).to be_present
    expect(entry.claim_notification!).to be_falsy
  end

  it "can still be claimed two days after it was published" do
    entry = create_entry
    entry.set(published_at: 2.days.ago.beginning_of_day)

    expect(entry).to be_notifiable
  end

  it "can't be claimed for an entry published three or more days ago, however recently it was added" do
    entry = create_entry
    entry.set(published_at: 3.days.ago.end_of_day)

    expect(entry).not_to be_notifiable
    expect(entry.claim_notification!).to be_falsy
  end

  # Today is the blog's day, not UTC's: 1 a.m. in India is still the day
  # before in UTC.
  it "counts the day in the blog's time zone" do
    travel_to Time.find_zone("Asia/Kolkata").local(2026, 10, 17, 1, 0) do
      entry = create_entry
      entry.set(published_at: Time.find_zone("Asia/Kolkata").local(2026, 10, 17, 0, 30))

      expect(entry).to be_notifiable
    end
  end

  it "mails every subscriber separately and records how many it reached" do
    entry = create_entry
    entry.claim_notification!

    expect(entry.notify_subscribers).to eq(2)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([["ada@domain.com"], ["grace@domain.com"]])
    expect(entry.reload.notified_count).to eq(2)
  end

  it "carries on past a failed address" do
    entry = create_entry
    entry.claim_notification!
    calls = 0
    allow(NewsletterMailer).to receive(:new_entry).and_wrap_original do |original, *args|
      (calls += 1) == 1 ? raise(Net::SMTPFatalError.new("550 no such user")) : original.call(*args)
    end

    expect(entry.notify_subscribers).to eq(1)
    expect(ActionMailer::Base.deliveries.map(&:to)).to eq([["grace@domain.com"]])
  end

  it "records who wasn't reached and why" do
    entry = create_entry
    entry.claim_notification!
    calls = 0
    allow(NewsletterMailer).to receive(:new_entry).and_wrap_original do |original, *args|
      (calls += 1) == 1 ? raise(Net::SMTPFatalError.new("550 no such user")) : original.call(*args)
    end

    entry.notify_subscribers

    failures = entry.reload.notification_failures
    expect(failures.map { |failure| failure.values_at("email", "error") }).to eq([["ada@domain.com", "Net::SMTPFatalError: 550 no such user"]])
    expect(failures.first["failed_at"]).to be_present
  end

  it "records nothing when every mail got through" do
    entry = create_entry
    entry.claim_notification!
    entry.notify_subscribers

    expect(entry.reload.notification_failures).to eq([])
  end

  it "releases the claim when no mail got through, so it can be tried again" do
    entry = create_entry
    entry.claim_notification!
    allow(NewsletterMailer).to receive(:new_entry).and_raise(Net::SMTPAuthenticationError.new("535 bad key"))

    expect(entry.notify_subscribers).to eq(0)
    expect(entry.reload).to be_notifiable
    expect(entry.notification_failures.map { |failure| failure["email"] }).to eq(["ada@domain.com", "grace@domain.com"])
  end

  describe "sending again to who it didn't reach" do
    def fail_first_send(entry)
      entry.claim_notification!
      calls = 0
      allow(NewsletterMailer).to receive(:new_entry).and_wrap_original do |original, *args|
        (calls += 1) == 1 ? raise(Net::SMTPFatalError.new("550 no such user")) : original.call(*args)
      end
      entry.notify_subscribers
      allow(NewsletterMailer).to receive(:new_entry).and_call_original
      ActionMailer::Base.deliveries.clear
    end

    it "mails only them, counting them in and clearing their failures" do
      entry = create_entry
      fail_first_send(entry)

      emails = entry.claim_resend!
      expect(emails).to eq(["ada@domain.com"])
      expect(entry.resend_to(emails)).to eq(1)

      expect(ActionMailer::Base.deliveries.map(&:to)).to eq([["ada@domain.com"]])
      expect(entry.reload.notified_count).to eq(2)
      expect(entry.notification_failures).to eq([])
    end

    it "can be claimed only once" do
      entry = create_entry
      fail_first_send(entry)

      expect(entry.claim_resend!).to eq(["ada@domain.com"])
      expect(FeedEntry.find(entry.url).claim_resend!).to eq([])
    end

    it "keeps whoever fails again" do
      entry = create_entry
      fail_first_send(entry)
      allow(NewsletterMailer).to receive(:new_entry).and_raise(Net::OpenTimeout.new("execution expired"))

      expect(entry.resend_to(entry.claim_resend!)).to eq(0)
      expect(entry.reload.notified_count).to eq(1)
      expect(entry.notification_failures.map { |failure| failure.values_at("email", "error") }).to eq([["ada@domain.com", "Net::OpenTimeout: execution expired"]])
    end

    it "skips anyone who has unsubscribed since" do
      entry = create_entry
      fail_first_send(entry)
      NewsletterSubscriber.where(email: "ada@domain.com").delete_all

      expect(entry.resend_to(entry.claim_resend!)).to eq(0)
      expect(ActionMailer::Base.deliveries).to be_empty
    end

    it "isn't offered while the entry can still be sent to everyone" do
      entry = create_entry
      entry.claim_notification!
      allow(NewsletterMailer).to receive(:new_entry).and_raise(Net::OpenTimeout.new("execution expired"))
      entry.notify_subscribers

      expect(entry.reload).to be_notifiable
      expect(entry).not_to be_resendable
      expect(entry.claim_resend!).to eq([])
    end

    it "marks an entry no one got as sent once a resend gets through, on a later day" do
      entry = create_entry
      entry.claim_notification!
      allow(NewsletterMailer).to receive(:new_entry).and_raise(Net::OpenTimeout.new("execution expired"))
      entry.notify_subscribers
      allow(NewsletterMailer).to receive(:new_entry).and_call_original

      travel FeedEntry::NOTIFY_DAYS.days do
        entry.reload
        expect(entry).to be_resendable
        expect(entry.resend_to(entry.claim_resend!)).to eq(2)
        expect(entry.reload.notified_at).to be_present
        expect(entry.notified_count).to eq(2)
      end
    end
  end
end
