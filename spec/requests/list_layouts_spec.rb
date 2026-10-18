# encoding: UTF-8

require "rails_helper"

RSpec.describe "List settings", type: :request do
  def headers
    Nokogiri::HTML5(response.body).css("thead th").map { |th| th.text.squish }.compact_blank
  end

  # reCAPTCHA logins is the list with both a layout and filter tabs.
  describe "a list with a layout" do
    let!(:accepted) { Google::Recaptcha::Assessment.create!(action: "LOGIN", score: 0.9, accepted: true, remote_ip: "203.0.113.1", created_at: Time.utc(2026, 7, 5)) }

    it "lists every list's layout" do
      get list_layouts_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include("reCAPTCHA logins", "Time, descending", "Default")
    end

    it "opens the dialog with each column in its zone" do
      ListSetting.create!(list: "recaptcha_assessments", hidden: %w[client])

      get edit_list_layout_path("recaptcha_assessments")

      html = Nokogiri::HTML5(response.body)
      expect(html.css("[data-zone=shown] input").map { |input| input["value"] }).to eq(%w[created_at action score outcome password])
      expect(html.css("[data-zone=hidden] input").map { |input| input["name"] }).to eq(%w[hidden[]])
    end

    it "reorders, hides and sorts a list, then resets it" do
      patch list_layout_path("recaptcha_assessments"),
        params: {shown: %w[score created_at], hidden: %w[action outcome password client], sort: "score", direction: "asc", per_page: "50"},
        headers: {"HTTP_REFERER" => google_recaptcha_logins_url}
      expect(response).to redirect_to(google_recaptcha_logins_url)

      get google_recaptcha_logins_path
      expect(headers).to eq(%w[# Score Time])
      expect(response.body).to include('aria-sort="ascending"')

      get list_layouts_path
      expect(response.body).to include("Customized", "Score, ascending")

      delete list_layout_path("recaptcha_assessments")
      expect(ListSetting.count).to eq(0)

      get google_recaptcha_logins_path
      expect(headers).to eq(%w[# Time Action Score Outcome Password Client])
    end

    it "opens a list on its default tab, dense, without row numbers and with a fixed header" do
      Google::Recaptcha::Assessment.create!(action: "LOGIN", score: 0.1, accepted: false, remote_ip: "198.51.100.7", created_at: Time.utc(2026, 7, 6))
      patch list_layout_path("recaptcha_assessments"), params: {tab: "no", density: "compact", row_numbers: "0", sticky_header: "1"}

      get google_recaptcha_logins_path
      html = Nokogiri::HTML5(response.body)
      expect(html.at_css("nav[aria-label='Filter by outcome'] a[aria-current=page]").text).to include("Rejected")
      expect(html.css("tbody tr").size).to eq(1)
      expect(html.at_css("nav a[href='/google/recaptcha/logins?accepted=all']")).to be_present
      expect(headers).to eq(%w[Time Action Score Outcome Password Client])
      expect(html.at_css("thead")["class"]).to include("sticky")
      expect(html.at_css("table")["class"]).to include("[&_td]:py-1")

      get google_recaptcha_logins_path(accepted: "all")
      expect(Nokogiri::HTML5(response.body).css("tbody tr").size).to eq(2)
    end
  end

  it "404s for an unknown list" do
    get edit_list_layout_path("nope")

    expect(response).to have_http_status(:not_found)
  end

  describe "saved searches" do
    it "saves the current search, links to it and removes it" do
      get messages_path(q: "hello", sort: "name", direction: "asc")
      expect(response.body).to include("Save search")

      post saved_searches_path, params: {list: "messages", name: "  Examples ", query: "direction=asc&q=hello&sort=name"},
        headers: {"HTTP_REFERER" => messages_url}
      expect(response).to redirect_to(messages_url)
      search = SavedSearch.find_by(name: "Examples")

      get messages_path
      expect(Nokogiri::HTML5(response.body).at_css("a[href='/messages?direction=asc&q=hello&sort=name']").text).to eq("Examples")

      get messages_path(q: "hello", sort: "name", direction: "asc")
      expect(response.body).not_to include("Save search")

      delete saved_search_path(search)
      expect(SavedSearch.count).to eq(0)
    end

    it "is offered in the search panel of a list without a layout and listed on its own page" do
      get messages_path(q: "hello")
      expect(Nokogiri::HTML5(response.body).at_css("details form input[name=list][value=messages]")).to be_present

      post saved_searches_path, params: {list: "messages", name: "Hellos", query: "q=hello"}
      get messages_path
      html = Nokogiri::HTML5(response.body)
      expect(html.at_css("details a[href='/messages?q=hello']").text).to eq("Hellos")
      expect(html.at_css("details").has_attribute?("open")).to be(true)

      get saved_searches_path
      expect(Nokogiri::HTML5(response.body).at_css("a[href='/messages?q=hello']").text).to eq("Hellos")
    end

    it "has its own page under Settings, empty until one is saved" do
      get saved_searches_path

      html = Nokogiri::HTML5(response.body)
      expect(response.body).to include("None saved yet.")
      expect(html.css("nav a").map { |link| link.text.squish }).to include("Saved searches")
      expect(html.at_css("nav a[href='/settings/saved-searches']")).to be_present
    end

    it "drops query values that aren't plain strings" do
      search = SavedSearch.new(query: "q=a&host[]=evil.example")

      expect(search.params).to eq("q" => "a")
    end

    it "isn't offered when the list is only sorted" do
      get messages_path(sort: "name", direction: "asc")

      expect(response.body).not_to include("Save search")
    end

    it "refuses a search that only sorts or pages the list" do
      post saved_searches_path, params: {list: "messages", name: "Sorted", query: "direction=asc&sort=name&page=2&q="}

      expect(SavedSearch.count).to eq(0)
      expect(flash[:alert]).to include("apply at least one filter first")
    end

    it "refuses a name that's blank, too short or too long" do
      {"   " => "Name can't be blank", "a" => "Name is too short (minimum is 2 characters)", "a" * 41 => "Name is too long (maximum is 40 characters)"}.each do |name, error|
        post saved_searches_path, params: {list: "messages", name: name, query: "q=a"}
        expect(flash[:alert]).to eq("Couldn't save the search: #{error}.")
      end

      expect(SavedSearch.count).to eq(0)
    end

    it "shows why it was refused under the form, keeping the name typed" do
      post saved_searches_path, params: {list: "messages", name: "a", query: "q=a"}, as: :turbo_stream

      expect(response).to have_http_status(:unprocessable_content)
      html = Nokogiri::HTML5(response.body)
      expect(html.at_css("turbo-stream[action=replace][target=saved-search-form]")).to be_present
      expect(html.at_css("template input#saved_search_name[aria-invalid=true]")["value"]).to eq("a")
      expect(html.at_css("template #saved-search-error").text.squish).to eq("Name is too short (minimum is 2 characters)")
      expect(flash[:alert]).to be_nil
      expect(SavedSearch.count).to eq(0)
    end

    it "refuses a list that doesn't exist" do
      post saved_searches_path, params: {list: "nope", name: "x", query: "q=a"}

      expect(SavedSearch.count).to eq(0)
      expect(flash[:alert]).to include("Couldn't save")
    end
  end
end
