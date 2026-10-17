# encoding: UTF-8

require "rails_helper"

RSpec.describe "Analytics page flow", type: :request do
  let(:service) { Google::Analytics::PageFlowService }

  def page
    Nokogiri::HTML5(response.body)
  end

  def flow(path)
    service::Flow.new(path: path, views: 45, readers: 30, next_pages: [["/post/ruby", 8]], previous: [
      service::Source.new(value: "/", kind: :page, views: 24), service::Source.new(value: "google.com", kind: :site, views: 15)
    ])
  end

  it "opens on the most read page, offering the rest to pick" do
    Google::Analytics::Stat.create!(date: 3.days.ago.to_date, page_path: "/about", views: 2)
    Google::Analytics::Stat.create!(date: 3.days.ago.to_date, page_path: "/post/rails", views: 9)
    allow(service).to receive(:call) { |_period, path:| service::Result.new(flow: flow(path), errors: []) }

    get google_analytics_page_flow_path

    expect(service).to have_received(:call).with(anything, path: "/post/rails")
    expect(page.css("#page-flow-pages option").map { |option| option["value"] }).to eq(["/post/rails", "/about"])
  end

  it "shows where the page's readers came from and went next, linking the blog's pages on" do
    allow(service).to receive(:call) { |_period, path:| service::Result.new(flow: flow(path), errors: []) }

    get google_analytics_page_flow_path(path: "https://example.com/post/rails?x=1")

    expect(service).to have_received(:call).with(anything, path: "/post/rails")
    came = page.css("#came-from ~ div tbody tr").map { |row| row.css("td").first(2).map { |td| td.text.strip } }
    expect(came).to eq([["/", "24"], ["google.com", "15"]])
    expect(page.at_css("#came-from ~ div a")["href"]).to include("path=%2F")
    expect(page.css("#went-to ~ div tbody td a").map(&:text)).to eq(["/post/ruby"])
  end

  it "says why when Analytics can't be read" do
    allow(service).to receive(:call) { service::Result.new(errors: ["Analytics page flow: quota exhausted"]) }

    get google_analytics_page_flow_path(path: "/")

    expect(page.at_css("[role=alert]").text).to include("quota exhausted")
  end
end
