# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics settings", type: :request do
  let(:service) { Google::Analytics::SettingsService }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "shows the property's settings and warns about the ones limiting reports" do
    settings = service::Settings.new(
      display_name: "Blog",
      time_zone: "Asia/Kolkata",
      event_retention: "TWO_MONTHS",
      reset_on_new_activity: true,
      key_events: [service::KeyEvent.new(event_name: "newsletter_subscribe", counting_method: "ONCE_PER_EVENT")],
      custom_dimensions: [],
      custom_metrics: [],
      google_signals: "GOOGLE_SIGNALS_DISABLED",
      annotations: [service.module_parent::AnnotationService::Annotation.new(title: "Published: Grid", date: Date.new(2026, 10, 1))],
      data_streams: [
        service::DataStream.new(
          display_name: "Blog",
          measurement_id: "G-ABC",
          enhanced_measurement: service::EnhancedMeasurement.new(stream_enabled: true, scrolls: true, outbound_clicks: false)
        )
      ]
    )
    allow(service).to receive(:call) { service::Result.new(settings: settings, errors: []) }

    get google_analytics_settings_path

    expect(response).to have_http_status(:ok)
    warnings = page.css("[role=alert] li").map { |item| item.text.squish }
    expect(warnings.first).to start_with("Event data is kept for only 2 months")
    expect(warnings.second).to start_with("contact_submit isn't marked as a key event")
    expect(page.css("#key-events ~ div tbody td").map { |td| td.text.strip }).to eq(["newsletter_subscribe", "Every time"])
    expect(page.css("section[aria-labelledby=annotations] tbody td").map { |td| td.text.squish }).to eq(["1 Oct 2026", "Published: Grid", "—"])
    expect(warnings).to include(start_with("Google signals is off"))
    expect(warnings.last).to start_with("Enhanced measurement on Blog doesn't send outbound link clicks")
    expect(page.css("#data-streams ~ div tbody td").map { |td| td.text.squish }.first(5)).to eq(["Blog", "G-ABC", "Yes", "Yes", "No"])
  end

  it "offers to register a missing custom dimension, and says how GA answered" do
    settings = service::Settings.new(event_retention: "FOURTEEN_MONTHS", key_events: [], custom_dimensions: [], custom_metrics: [], data_streams: [])
    allow(service).to receive(:call) { service::Result.new(settings: settings, errors: []) }
    allow(Google::Analytics::CustomDimensionService).to receive(:call) { SyncResult.new(1, 0, 0, []) }

    get google_analytics_settings_path
    expect(page.at_css("[role=alert]").text.squish).to include("event_label, metric_rating, content_category, content_tags, link_domain, and outbound aren't registered")
    expect(page.at_css("[role=alert]").text.squish).to include("read_seconds isn't registered as an event-scoped custom metric")

    post google_analytics_settings_custom_dimensions_path(parameter_name: "event_label")
    expect(response).to redirect_to(google_analytics_settings_path)
    expect(flash[:notice]).to start_with("Registered event_label")
    expect(Google::Analytics::CustomDimensionService).to have_received(:call).with("event_label")

    post google_analytics_settings_custom_dimensions_path(parameter_name: "read_seconds")
    expect(flash[:notice]).to start_with("Registered read_seconds as a custom metric")
  end

  it "queues marking recent entries on GA's charts" do
    expect { post google_analytics_settings_annotations_path }.to have_enqueued_job(Google::Analytics::AnnotationJob)

    expect(response).to redirect_to(google_analytics_settings_path)
    expect(SyncRequest.where(kind: "analytics_annotations").count).to eq(1)
  end

  it "refuses a dimension the blog doesn't send" do
    post google_analytics_settings_custom_dimensions_path(parameter_name: "anything")

    expect(flash[:alert]).to eq("Unknown custom dimension or metric.")
  end

  it "says why when Analytics can't be read" do
    allow(service).to receive(:call) { service::Result.new(settings: nil, errors: ["Analytics settings: no access"]) }

    get google_analytics_settings_path

    expect(page.at_css("[role=alert]").text).to include("no access")
  end
end
