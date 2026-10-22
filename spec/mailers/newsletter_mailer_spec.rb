# encoding: UTF-8

require "rails_helper"

RSpec.describe NewsletterMailer, type: :mailer do
  let(:entry) do
    FeedEntry.create!(url: "https://blog.example.com/tutorials/grid", name: "Mastering <Grid>", type: "tutorial",
      description: "Lay out anything.", published_at: 10.days.ago, last_modified_at: 10.days.ago)
  end
  let(:subscriber) { NewsletterSubscriber.create!(email: "reader@domain.com", subscribed_at: 1.month.ago) }

  # The blog's address comes from the sitemap's, and sending needs a sender
  # and an unsubscribe secret, so specs don't depend on whatever the local
  # credentials hold (CI has none).
  before do
    ActionMailer::Base.deliveries.clear
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:sitemap, :url) { "https://blog.example.com/sitemap.xml" }
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :from) { "Blog <blog@domain.com>" }
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :unsubscribe_secret) { "test-secret" }
  end

  it "delivers itself, naming the entry's type, escaped, with a link to it" do
    message = described_class.new_entry(entry, subscriber).message

    expect(ActionMailer::Base.deliveries).to eq([message])
    expect(message.to).to eq(["reader@domain.com"])
    expect(message.subject).to eq("New tutorial: Mastering <Grid>")
    unsubscribe = "https://blog.example.com/unsubscribe/#{subscriber.unsubscribe_token}"
    expect(message["List-Unsubscribe"].value).to eq("<https://blog.example.com/api/unsubscribe/#{subscriber.unsubscribe_token}>")
    expect(message["List-Unsubscribe-Post"].value).to eq("List-Unsubscribe=One-Click")
    expect(message.html_part.body.to_s).to include(%(href="#{unsubscribe}"))
    expect(message.text_part.body.to_s).to include("Unsubscribe: #{unsubscribe}")
    expect(message.html_part.body.to_s).to include("Mastering &lt;Grid&gt;", 'href="https://blog.example.com/tutorials/grid?',
      "Read the tutorial →", 'href="https://blog.example.com?')
    expect(message.text_part.body.to_s).to include("Read the tutorial: https://blog.example.com/tutorials/grid")
  end

  it "tags each link to the blog with the newsletter campaign and which link it was" do
    message = described_class.new_entry(entry, subscriber).message
    html = message.html_part.body.to_s
    tags = "utm_source=newsletter&amp;utm_medium=email&amp;utm_campaign=new_entry"

    expect(html).to include(%(href="https://blog.example.com/tutorials/grid?#{tags}&amp;utm_content=title"),
      %(href="https://blog.example.com/tutorials/grid?#{tags}&amp;utm_content=button"),
      %(href="https://blog.example.com?#{tags}&amp;utm_content=header"), %(href="https://blog.example.com?#{tags}&amp;utm_content=footer"))
    expect(message.text_part.body.to_s).to include("https://blog.example.com/tutorials/grid?#{tags.gsub("&amp;", "&")}&utm_content=text")
    expect(html).to include(%(href="https://blog.example.com/unsubscribe/#{subscriber.unsubscribe_token}"))
  end

  # Brevo hands the tag back on the events it posts for the mail.
  it "tags the mail with the entry's URL" do
    message = described_class.new_entry(entry, subscriber).message

    expect(message["X-Mailin-Tag"].value).to eq("https://blog.example.com/tutorials/grid")
  end

  it "shows the blog's logo from the blog itself" do
    message = described_class.new_entry(entry, subscriber).message

    expect(message.html_part.body.to_s).to include('src="https://blog.example.com/assets/img/icons/favicon.png"', 'width="60"')
  end

  # The app's log, which Rails writes its own lines to as well.
  it "logs the delivery" do
    allow(Rails.logger).to receive(:info).and_call_original
    expect(Rails.logger).to receive(:info).with("[new_entry] Delivered to reader@domain.com")

    described_class.new_entry(entry, subscriber).message
  end

  it "logs a failed delivery and raises it" do
    allow_any_instance_of(Mail::Message).to receive(:deliver!).and_raise(Net::SMTPAuthenticationError.new("535 bad key"))
    allow(Rails.logger).to receive(:error).and_call_original
    expect(Rails.logger).to receive(:error).with("[new_entry] Failed: 535 bad key")

    expect { described_class.new_entry(entry, subscriber).message }.to raise_error(Net::SMTPAuthenticationError)
  end
end
