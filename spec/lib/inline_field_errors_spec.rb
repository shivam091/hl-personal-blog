# encoding: UTF-8

require "rails_helper"

RSpec.describe InlineFieldErrors, type: :helper do
  let(:record) do
    ListSpecDocument.new.tap do |doc|
      doc.errors.add(:url, :blank)
      doc.errors.add(:url, "must be an http(s) URL")
      doc.errors.add(:indexed, "must be yes or no")
      doc.errors.add(:base, "Google rejected this page")
    end
  end

  def render_form(&block)
    Nokogiri::HTML5.fragment(helper.form_with(model: record, url: "/pages", &block))
  end

  it "puts a field's full messages right below it, linked for screen readers" do
    html = render_form { |form| form.label(:url) + form.text_field(:url) }

    input = html.at_css("input#list_spec_document_url")
    expect(input["aria-invalid"]).to eq("true")
    expect(input["aria-describedby"]).to eq("list_spec_document_url_error")
    expect(input.next_element["id"]).to eq("list_spec_document_url_error")
    expect(html.css("#list_spec_document_url_error p").map { |p| p.text.strip }).to eq([
      "Url can't be blank",
      "Url must be an http(s) URL"
    ])
  end

  it "replaces Rails' wrapper div, leaving labels untouched" do
    html = render_form { |form| form.label(:url) + form.text_field(:url) }

    expect(html.css(".field_with_errors")).to be_empty
    expect(html.at_css("label")["aria-invalid"]).to be_nil
  end

  it "gives a check box one message, below its row, not on its hidden input" do
    html = render_form { |form| form.check_box(:indexed) }

    expect(html.css("input[type=hidden][aria-invalid]")).to be_empty
    expect(html.at_css("input[type=checkbox]")["aria-invalid"]).to eq("true")
    expect(html.css("[id$=_error]").size).to eq(1)
    expect(html.at_css("#list_spec_document_indexed_error")["class"]).to include("order-last", "basis-full")
  end

  it "leaves fields without errors alone" do
    html = render_form { |form| form.text_field(:last_modified_at) }

    expect(html.at_css("input")["aria-invalid"]).to be_nil
    expect(html.css("[id$=_error]")).to be_empty
  end

  describe "the error summary" do
    it "counts every problem and lists record-wide ones" do
      html = Nokogiri::HTML5.fragment(helper.render("shared/error_summary", record: record))

      expect(html.at_css("[role=alert] h2").text.squish).to eq("4 problems kept this list spec document from being saved")
      expect(html.css("li").map(&:text)).to eq(["Google rejected this page"])
      expect(html.text).to include("Fix the highlighted fields below.")
    end
  end
end
