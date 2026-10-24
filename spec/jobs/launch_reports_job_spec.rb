# encoding: UTF-8

require "rails_helper"

RSpec.describe LaunchReportsJob do
  let(:today) { Date.new(2026, 10, 20) }

  before do
    ActionMailer::Base.deliveries.clear
    allow(Rails.application.credentials).to receive(:dig).and_call_original
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :from) { "Blog <blog@domain.com>" }
    allow(Rails.application.credentials).to receive(:dig).with(:mailer, :notify_to) { "me@domain.com" }
  end

  def entry(name, published:)
    FeedEntry.create!(url: "https://blog.example.com/post/#{name}", name: name, type: "post",
      published_at: published.in_time_zone.change(hour: 9), last_modified_at: published.in_time_zone.change(hour: 9))
  end

  it "mails each entry's report on its 7th and 30th day, once however often it runs" do
    entry("week", published: today - 7)
    entry("late", published: today - 9)
    entry("month", published: today - 30)
    entry("tomorrow", published: today - 6)
    entry("old", published: today - 7 - LaunchReportsJob::CATCH_UP_DAYS - 1)

    expect(described_class.perform_now(today: today)).to eq(3)
    expect(described_class.perform_now(today: today)).to eq(0)

    expect(ActionMailer::Base.deliveries.map(&:subject)).to contain_exactly(
      a_string_starting_with("Day 7: week"), a_string_starting_with("Day 7: late"), a_string_starting_with("Day 30: month")
    )
    expect(LaunchReportDelivery.where(:sent_at.ne => nil).pluck(:entry_url, :age)).to contain_exactly(
      ["https://blog.example.com/post/week", 7], ["https://blog.example.com/post/late", 7], ["https://blog.example.com/post/month", 30]
    )
  end

  it "gives a report whose mail failed back, so the next run tries it again" do
    entry("week", published: today - 7)
    allow(AdminMailer).to receive(:launch_report).and_raise(StandardError, "550 rejected")

    expect { described_class.perform_now(today: today) }.to raise_error(RuntimeError, /post\/week \(day 7\): 550 rejected/)
    expect(LaunchReportDelivery.count).to eq(0)
  end
end
