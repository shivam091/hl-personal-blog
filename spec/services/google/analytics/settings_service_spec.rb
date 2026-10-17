# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::SettingsService do
  let(:base) { "https://analyticsadmin.googleapis.com/v1beta/properties/123456789" }
  let(:cache) { ActiveSupport::Cache::MemoryStore.new }
  let(:enhanced_measurement) { [200, {}, {streamEnabled: true, scrollsEnabled: true, outboundClicksEnabled: false, fileDownloadsEnabled: true, pageChangesEnabled: true}.to_json] }

  def settings(property: 123456789)
    described_class.new(property: property, client: google_client, cache: cache).call
  end

  before do
    google_stubs.get(base) { [200, {}, {displayName: "Blog", timeZone: "Asia/Kolkata"}.to_json] }
    google_stubs.get("#{base}/dataRetentionSettings") {
      [200, {}, {eventDataRetention: "TWO_MONTHS", resetUserDataOnNewActivity: true}.to_json]
    }
    google_stubs.get("#{base}/keyEvents") do |env|
      if env.params["pageToken"]
        [200, {}, {keyEvents: [{eventName: "newsletter_subscribe", countingMethod: "ONCE_PER_EVENT"}]}.to_json]
      else
        [200, {}, {keyEvents: [{eventName: "purchase", countingMethod: "ONCE_PER_EVENT"}], nextPageToken: "next"}.to_json]
      end
    end
    google_stubs.get("#{base}/customDimensions") {
      [200, {}, {customDimensions: [{displayName: "Results", parameterName: "results_count", scope: "EVENT"}]}.to_json]
    }
    google_stubs.get("#{base}/customMetrics") {
      [200, {}, {customMetrics: [{displayName: "Read seconds", parameterName: "read_seconds", scope: "EVENT", measurementUnit: "SECONDS"}]}.to_json]
    }
    google_stubs.get("https://analyticsadmin.googleapis.com/v1alpha/properties/123456789/reportingDataAnnotations") {
      [200, {}, {reportingDataAnnotations: [
        {title: "Published: Grid", annotationDate: {year: 2026, month: 10, day: 1}},
        {title: "Data deleted", systemGenerated: true, annotationDateRange: {startDate: {year: 2026, month: 10, day: 5}, endDate: {year: 2026, month: 10, day: 6}}}
      ]}.to_json]
    }
    google_stubs.get("https://analyticsadmin.googleapis.com/v1alpha/properties/123456789/googleSignalsSettings") {
      [200, {}, {state: "GOOGLE_SIGNALS_DISABLED"}.to_json]
    }
    google_stubs.get("#{base}/dataStreams") {
      [200, {}, {dataStreams: [
        {
          name: "properties/123456789/dataStreams/1",
          type: "WEB_DATA_STREAM",
          displayName: "Blog",
          webStreamData: {measurementId: "G-ABC", defaultUri: "https://harshal-ladhe.vercel.app"}
        },
        {
          name: "properties/123456789/dataStreams/2",
          type: "ANDROID_APP_DATA_STREAM",
          displayName: "App"
        }
      ]}.to_json]
    }
    google_stubs.get("https://analyticsadmin.googleapis.com/v1alpha/properties/123456789/dataStreams/1/enhancedMeasurementSettings") { enhanced_measurement }
  end

  it "reads retention, every page of key events, and custom dimensions" do
    result = settings

    expect(result.errors).to eq([])
    expect(result.settings).to have_attributes(
      display_name: "Blog",
      time_zone: "Asia/Kolkata",
      retention_label: "2 months",
      reset_on_new_activity: true
    )
    expect(result.settings.key_events.map(&:event_name)).to eq(%w[newsletter_subscribe purchase])
    expect(result.settings.custom_dimensions.map(&:parameter_name)).to eq(["results_count"])
  end

  it "flags two months of event data and conversions not marked as key events" do
    expect(settings.settings).to have_attributes(short_retention?: true, missing_key_events: %w[contact_submit article_read like sandbox_download sandbox_open_external share])
  end

  it "flags the blog's event parameters not registered as event-scoped dimensions or metrics" do
    expect(settings.settings.missing_custom_dimensions).to eq(%w[event_label metric_rating content_category content_tags link_domain outbound method])
    expect(settings.settings.custom_metrics.sole).to have_attributes(parameter_name: "read_seconds", measurement_unit: "SECONDS")
    expect(settings.settings.missing_custom_metrics).to eq([])
  end

  it "reads each web stream's enhanced measurement, flagging the events reports here rely on that it doesn't send" do
    stream = settings.settings.data_streams.sole

    expect(stream).to have_attributes(
      display_name: "Blog",
      measurement_id: "G-ABC",
      url: "https://harshal-ladhe.vercel.app"
    )
    expect(stream.enhanced_measurement).to have_attributes(
      scrolls: true,
      outbound_clicks: false,
      file_downloads: true
    )
    expect(stream.missing_enhanced_measurement).to eq([:outbound_clicks])
  end

  it "flags every expected event when the stream's enhanced measurement is off" do
    stream = described_class::DataStream.new(
      enhanced_measurement: described_class::EnhancedMeasurement.new(
        stream_enabled: false,
        scrolls: true,
        outbound_clicks: true
      )
    )

    expect(stream.missing_enhanced_measurement).to eq(%i[scrolls outbound_clicks])
  end

  it "flags history-change page views, which the blog already sends itself" do
    expect(settings.settings.data_streams.sole.unwanted_enhanced_measurement).to eq([:page_changes])
  end

  it "doesn't flag history-change page views while the stream's enhanced measurement is off" do
    stream = described_class::DataStream.new(
      enhanced_measurement: described_class::EnhancedMeasurement.new(stream_enabled: false, page_changes: true)
    )

    expect(stream.unwanted_enhanced_measurement).to eq([])
  end

  it "flags Google signals being off, which age and gender need" do
    expect(settings.settings).to have_attributes(google_signals: "GOOGLE_SIGNALS_DISABLED", google_signals_off?: true)
    expect(described_class::Settings.new(google_signals: nil).google_signals_off?).to be(false)
  end

  it "lists annotations newest first, dating a range by its start" do
    expect(settings.settings.annotations.map { |annotation| [annotation.title, annotation.date, annotation.system_generated] }).to eq([
      ["Data deleted", Date.new(2026, 10, 5), true], ["Published: Grid", Date.new(2026, 10, 1), nil]
    ])
  end

  context "when GA refuses the alpha call" do
    let(:enhanced_measurement) { [404, {}, {error: {message: "Not found"}}.to_json] }

    it "still reads the rest, leaving enhanced measurement unknown rather than off" do
      result = settings

      expect(result.errors).to eq([])
      expect(result.settings.data_streams.sole).to have_attributes(
        enhanced_measurement: nil,
        missing_enhanced_measurement: [],
        unwanted_enhanced_measurement: []
      )
    end
  end

  it "reports GA's refusal" do
    google_stubs.get(base.sub("123456789", "1")) { [403, {}, {error: {message: "The caller does not have permission"}}.to_json] }

    expect(settings(property: 1).errors).to eq(["Analytics settings: The caller does not have permission"])
  end
end
