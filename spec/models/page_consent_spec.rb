# encoding: UTF-8

require "rails_helper"

RSpec.describe PageConsent, type: :model do
  let(:period) { Period.new({from: "2026-10-10", to: "2026-10-11"}) }

  def page(slug, by_day, **tallies)
    PageView.collection.insert_one({"_id" => slug, "slug" => slug, "countriesByDay" => by_day.transform_values { {"IN" => it} }}.merge(tallies.transform_keys(&:to_s)))
    PageView.find(slug)
  end

  def analytics(path, views, date: Date.new(2026, 10, 10))
    Google::Analytics::Stat.create!(date: date, page_path: path, views: views)
  end

  before do
    # Ordinary pages losing 20%, so the median is 20%.
    %w[/a /b /c].each do |slug|
      page(slug, {"2026-10-10" => 100})
      analytics(slug, 80)
    end
  end

  it "names the page's consent states and sets its gap against the median" do
    view = page("/busy", {"2026-10-10" => 100}, consentByDay: {"2026-10-10" => {"granted" => 50, "denied" => 20, "pending" => 10, "default" => 20},
      "2026-10-01" => {"denied" => 99}})
    analytics("/busy", 50)

    consent = described_class.new(view, period)

    expect(consent.states).to eq("Granted" => 50, "Denied" => 20, "Pending" => 10, "No banner needed" => 20)
    expect(consent).to have_attributes(percent: 0.5, median_percent: 0.2, flagged?: true)
  end

  it "puts the gap down to causes as the site's snapshots do, scaling what GA could only have seen for some" do
    view = page("/busy", {"2026-10-10" => 100},
      consentByDay: {"2026-10-10" => {"granted" => 50, "denied" => 20, "pending" => 10, "default" => 20}},
      gaByDay: {"2026-10-10" => {"loaded" => 80, "blocked" => 10}}, suspectByDay: {"2026-10-10" => {"datacentre" => 5}})
    analytics("/busy", 50)

    consent = described_class.new(view, period)

    # 70% of readers could be seen, so 10 blocked count as 7, 10 undetected as 7 and 5 datacentre as 4 (rounded).
    expect(consent.causes).to eq(denied_gap: 20, pending_gap: 10, blocked_gap: 7, unknown_gap: 7, datacentre_gap: 4)
    expect(consent.unexplained).to eq(2)
    expect(consent).to be_complete
    expect(consent).to have_attributes(days_explained: 1, days_compared: 1)
  end

  it "leaves the unexplained rest out while some days' split isn't known" do
    view = page("/busy", {"2026-10-10" => 100, "2026-10-11" => 50},
      consentByDay: {"2026-10-10" => {"denied" => 30, "granted" => 70}, "2026-10-11" => {"unset" => 50}})
    analytics("/busy", 60)
    analytics("/busy", 40, date: Date.new(2026, 10, 11))

    consent = described_class.new(view, period)

    expect(consent.causes[:denied_gap]).to eq(30)
    expect(consent).to have_attributes(days_explained: 1, days_compared: 2, unexplained: nil)
    expect(consent.states).to eq("Granted" => 70, "Denied" => 30, "Unknown" => 50)
  end

  it "has no gap to explain when GA counts as many views as the blog" do
    view = page("/busy", {"2026-10-10" => 30}, consentByDay: {"2026-10-10" => {"denied" => 5, "granted" => 25}})
    analytics("/busy", 30)

    expect(described_class.new(view, period)).not_to be_gap
  end

  it "has nothing to show for a page without consent data in the period" do
    view = page("/old", {"2026-10-10" => 30}, consentByDay: {"2026-09-01" => {"granted" => 5}})

    consent = described_class.new(view, period)

    expect(consent).not_to be_any
  end
end
