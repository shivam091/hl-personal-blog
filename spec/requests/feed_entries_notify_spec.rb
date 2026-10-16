# encoding: UTF-8

require "rails_helper"

RSpec.describe "Notifying subscribers about a feed entry", type: :request do
  let!(:entry) do
    FeedEntry.create!(url: "https://blog.example.com/posts/new", name: "Hello", type: "post",
      published_at: Time.current, last_modified_at: Time.current)
  end

  before { NewsletterSubscriber.create!(email: "ada@domain.com", subscribed_at: 1.month.ago) }

  it "offers it only on entries published in the last few days" do
    FeedEntry.create!(url: "https://blog.example.com/posts/old", name: "Old", type: "post",
      published_at: FeedEntry::NOTIFY_DAYS.days.ago.end_of_day, last_modified_at: Time.current)

    get feed_entries_path

    expect(response.body).to include(%(action="#{notify_feed_entry_path(entry)}"))
    expect(response.body.scan(%r{action="[^"]*/notify"}).size).to eq(1)
  end

  it "mails subscribers in the background, once" do
    expect { post notify_feed_entry_path(entry) }.to have_enqueued_job(NotifySubscribersJob).with(entry.url)
    expect(flash[:notice]).to eq("Emailing 1 subscriber about Hello in the background.")

    expect { post notify_feed_entry_path(entry) }.not_to have_enqueued_job(NotifySubscribersJob)
    expect(flash[:alert]).to start_with("Subscribers can only be notified once")
  end

  it "shows it as sent afterwards" do
    entry.claim_notification!
    entry.set(notified_count: 1)

    get feed_entries_path

    expect(response.body).not_to include(notify_feed_entry_path(entry))
    expect(response.body).to include("Sent to 1 subscriber")
  end

  describe "sending again to undelivered addresses" do
    before do
      entry.claim_notification!
      entry.set(notified_count: 0, notification_failures: [{"email" => "ada@domain.com", "error" => "Net::OpenTimeout: execution expired", "failed_at" => Time.current}])
    end

    it "lists them on the entry with a way to send again" do
      get feed_entry_path(entry)

      expect(response.body).to include("Undelivered emails", "ada@domain.com", "Net::OpenTimeout: execution expired")
      expect(response.body).to include(%(action="#{resend_feed_entry_path(entry)}"))
    end

    it "mails them in the background, once" do
      expect { post resend_feed_entry_path(entry) }.to have_enqueued_job(NotifySubscribersJob).with(entry.url, ["ada@domain.com"])
      expect(flash[:notice]).to eq("Sending Hello again to 1 address in the background.")

      expect { post resend_feed_entry_path(entry) }.not_to have_enqueued_job(NotifySubscribersJob)
      expect(flash[:alert]).to eq("There are no undelivered emails to send again.")
    end
  end
end
