# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics funnel definitions", type: :request do
  let(:model) { Google::Analytics::FunnelDefinition }

  def page
    Nokogiri::HTML5(response.body)
  end

  it "lists the funnels, the blog's own to start with" do
    get google_analytics_funnel_definitions_path

    expect(response).to have_http_status(:ok)
    expect(page.css("tbody tr").map { |row| row["id"] }).to eq(%w[funnel-definition-newsletter funnel-definition-contact funnel-definition-share funnel-definition-resume])
  end

  it "adds a funnel from the form, skipping the blank steps" do
    get new_google_analytics_funnel_definition_path
    expect(page.css("input[name$='[event]']").size).to eq(2)

    post google_analytics_funnel_definitions_path, params: {google_analytics_funnel_definition: {title: "Reading to watching", key: "talks", position: "4",
      steps_attributes: {"0" => {name: "Visited the blog", event: "session_start", site: "1"},
        "1" => {name: "Watched a talk", event: "video_start", paths_list: "/talks/", site: "1"},
        "2" => {name: "", event: "", path: "", paths_list: "", site: "1"}}}}

    expect(response).to redirect_to(google_analytics_funnel_definitions_path)
    expect(model.find_by(key: "talks").steps.map(&:name)).to eq(["Visited the blog", "Watched a talk"])
  end

  it "shows what's wrong beside the form" do
    post google_analytics_funnel_definitions_path, params: {google_analytics_funnel_definition: {title: "", key: "talks",
      steps_attributes: {"0" => {name: "Visited the blog", event: "session_start"}}}}

    expect(response).to have_http_status(:unprocessable_content)
    expect(page.at_css("[role=alert]").text).to include("kept this")
    expect(page.text).to include("Steps need at least two")
  end

  it "edits a funnel's steps, removing one ticked to go" do
    funnel = model.all_or_defaults.find { |definition| definition.key == "newsletter" }
    read = funnel.steps.second

    get edit_google_analytics_funnel_definition_path(funnel)
    expect(response).to have_http_status(:ok)

    patch google_analytics_funnel_definition_path(funnel), params: {google_analytics_funnel_definition: {title: "Visiting to subscribing",
      steps_attributes: {"0" => {id: read.id, _destroy: "1"}}}}

    expect(response).to redirect_to(google_analytics_funnel_definitions_path)
    expect(funnel.reload.title).to eq("Visiting to subscribing")
    expect(funnel.steps.map(&:name)).to eq(["Visited the blog", "Subscribed to the newsletter"])
  end

  it "deletes a funnel" do
    funnel = model.all_or_defaults.first

    delete google_analytics_funnel_definition_path(funnel)

    expect(response).to redirect_to(google_analytics_funnel_definitions_path)
    expect(model.where(key: funnel.key)).not_to exist
  end
end
