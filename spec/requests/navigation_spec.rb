# encoding: UTF-8

require "rails_helper"

RSpec.describe "Navigation", type: :request do
  it "points every entry in config/navigation.yml at a real route" do
    routes = NavigationHelper.flat_entries.map { |link| link[:route] }

    routes.each do |route|
      expect(Rails.application.routes.url_helpers).to respond_to(:"#{route}_path"), "no route named #{route}"
    end
  end

  describe "breadcrumbs" do
    def crumbs
      Nokogiri::HTML5(response.body).css("nav[aria-label=Breadcrumb] li").map { |crumb| crumb.text.squish }
    end

    def current
      Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breadcrumb] [aria-current=page]")&.text&.squish
    end

    it "traces the menus to the current page, with none on the dashboard" do
      get content_report_path
      expect(crumbs).to eq(%w[Dashboard Reports Content])
      expect(current).to eq("Content")

      get google_analytics_acquisition_path
      expect(crumbs).to eq(["Dashboard", "Google", "Analytics", "Acquisition", "User acquisition"])

      get root_path
      expect(crumbs).to be_empty
    end

    it "ends on a report's tab, linking back to the report, the first tab included" do
      get google_search_console_performance_breakdown_path("query-pages")
      expect(crumbs).to eq(["Dashboard", "Google", "Search Console", "Performance", "Queries + pages"])
      expect(current).to eq("Queries + pages")
      expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breadcrumb] a[href='#{google_search_console_performance_path}']")).to be_present

      get google_search_console_performance_path
      expect(crumbs).to eq(["Dashboard", "Google", "Search Console", "Performance", "Pages"])
    end

    it "names a list's chosen filter tab, but not All" do
      get feed_entries_path(type: "post")
      expect(crumbs).to eq(["Dashboard", "Blog", "Feed entries", "Posts"])

      get feed_entries_path
      expect(crumbs).to eq(["Dashboard", "Blog", "Feed entries"])
    end

    it "ends on a record's own name, whichever name its section has in the title" do
      get google_analytics_event_path("click")

      expect(crumbs).to eq(["Dashboard", "Google", "Analytics", "Engagement", "click"])
    end

    it "links back to the list from a record's own page, ending on the record" do
      PageView.collection.insert_one("_id" => "/post/a", "slug" => "/post/a")

      get page_view_path("/post/a")

      expect(crumbs).to eq(["Dashboard", "Blog", "Page views", "/post/a"])
      expect(Nokogiri::HTML5(response.body).at_css("nav[aria-label=Breadcrumb] a[href='#{page_views_path}']")).to be_present
      expect(current).to eq("/post/a")
    end
  end

  describe "on a phone" do
    def page
      Nokogiri::HTML5(response.body)
    end

    before { get content_report_path }

    it "folds the menus behind a button that controls a hidden panel" do
      button = page.at_css("nav[aria-label=Main] button[aria-controls=mobile-nav]")
      expect(button["aria-expanded"]).to eq("false")
      expect(button["aria-label"]).to eq("Menu")
      expect(page.at_css("#mobile-nav")["hidden"]).not_to be_nil
    end

    it "says where you are and opens only the current page's section" do
      expect(page.at_css("nav[aria-label=Main] p.md\\:hidden").text.squish).to eq("Reports › Content")
      open = page.css("#mobile-nav details[open] summary").map { |summary| summary.text.squish }
      expect(open).to eq(["Reports"])
      expect(page.css("#mobile-nav details").map { |details| details["name"] }.uniq).to eq(["mobile-nav-section"])
      expect(page.at_css("#mobile-nav a[aria-current=page]").text.squish).to eq("Content")
    end

    it "names every menu a submenu's page is under" do
      get google_analytics_funnels_path
      expect(page.at_css("nav[aria-label=Main] p.md\\:hidden").text.squish).to eq("Google › Analytics › Funnels")
    end

    it "lists a submenu's pages under its heading and offers sign out" do
      google = page.css("#mobile-nav details").find { |details| details.at_css("summary").text.squish == "Google" }
      analytics = google.css("ul[aria-label]").find { |list| list["aria-label"] == "Analytics" }
      expect(analytics.css("a").map { |link| link.text.squish }).to include("Acquisition", "Settings")
      expect(page.at_css("#mobile-nav form[action='#{session_path}'] button").text.squish).to eq("Sign out")
    end
  end
end
