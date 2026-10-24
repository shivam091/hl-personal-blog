# encoding: UTF-8

require "rails_helper"

RSpec.describe LaunchGaShare, type: :model do
  let(:days) { Date.new(2026, 10, 10)..Date.new(2026, 10, 16) }

  def views(by_day)
    PageView.collection.insert_one("_id" => "/post/new", "slug" => "/post/new", "countriesByDay" => by_day.transform_values { |count| {"IN" => count} })
  end

  def analytics(path, day, count)
    Google::Analytics::Stat.create!(date: Date.iso8601(day), page_path: path, views: count)
  end

  it "sets GA's views of the entry, at any address, against ours on the days GA has synced" do
    views("2026-10-10" => 60, "2026-10-11" => 40, "2026-10-16" => 500)
    analytics("/post/new/", "2026-10-10", 20)
    analytics("/post/new?utm_source=x", "2026-10-11", 10)
    analytics("/post/newer", "2026-10-11", 99)

    expect(described_class.new("/post/new", days).share).to eq(0.3)
  end

  it "has none when either side is under the minimum, or GA hasn't synced the days" do
    views("2026-10-10" => 100)
    expect(described_class.new("/post/new", days).share).to be_nil

    analytics("/post/new", "2026-10-10", PageGap::MIN_VIEWS - 1)
    expect(described_class.new("/post/new", days).share).to be_nil
  end
end
