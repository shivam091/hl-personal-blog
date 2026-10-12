# encoding: UTF-8

require "rails_helper"

RSpec.describe Blog do
  def stub_url(url)
    allow(Rails.application.credentials).to receive(:blog) { {url: url} }
  end

  it "builds the logo address from the blog's own" do
    stub_url("https://blog.example.com/")

    expect(described_class.url).to eq("https://blog.example.com")
    expect(described_class.logo_url).to eq("https://blog.example.com/assets/img/icons/favicon.png")
  end

  it "gives none of them while the address isn't set" do
    allow(Rails.application.credentials).to receive(:blog) { nil }

    expect([described_class.url, described_class.logo_url]).to all(be_nil)
  end
end
