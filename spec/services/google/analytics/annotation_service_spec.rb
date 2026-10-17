# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::AnnotationService do
  let(:url) { "https://analyticsadmin.googleapis.com/v1alpha/properties/123456789/reportingDataAnnotations" }
  let(:today) { Date.new(2026, 10, 20) }
  let(:created) { [] }

  def entry(name, published_at)
    FeedEntry.create!(url: "https://blog.example.com/#{name.parameterize}", name: name, type: "post",
      published_at: published_at, last_modified_at: published_at)
  end

  def annotate
    described_class.call(property: 123456789, client: google_client, today: today)
  end

  def stub_annotations(existing)
    google_stubs.get(url) { [200, {}, {reportingDataAnnotations: existing}.to_json] }
    google_stubs.post(url) do |env|
      created << JSON.parse(env.body)
      [200, {}, {}.to_json]
    end
  end

  it "marks each recent entry's publishing day once, leaving older entries and ones already marked alone" do
    entry("CSS Grid", Time.zone.local(2026, 10, 18, 9))
    entry("Flexbox", Time.zone.local(2026, 10, 10, 9))
    entry("Old post", Time.zone.local(2026, 8, 1, 9))
    stub_annotations([{title: "Published: Flexbox", annotationDate: {year: 2026, month: 10, day: 10}}])

    expect(annotate.summary).to eq("1 created, 0 updated, 1 unchanged, 0 failed")
    expect(created).to eq([{
      "title" => "Published: CSS Grid", "description" => "https://blog.example.com/css-grid", "color" => "BLUE",
      "annotationDate" => {"year" => 2026, "month" => 10, "day" => 18}
    }])
  end

  it "cuts a long title to GA's limit, and compares the cut one" do
    long = entry("A very long title that goes well past what GA allows", Time.zone.local(2026, 10, 18, 9))
    stub_annotations([{title: described_class.title_for(long), annotationDate: {year: 2026, month: 10, day: 18}}])

    expect(described_class.title_for(long).length).to eq(described_class::TITLE_LIMIT)
    expect(annotate.created).to eq(0)
  end

  it "reports GA's refusal, such as a Viewer-only service account" do
    entry("CSS Grid", Time.zone.local(2026, 10, 18, 9))
    google_stubs.get(url) { [200, {}, {}.to_json] }
    google_stubs.post(url) { [403, {}, {error: {message: "The caller does not have permission"}}.to_json] }

    expect(annotate.errors).to eq(["Annotation for CSS Grid: The caller does not have permission"])
  end
end
