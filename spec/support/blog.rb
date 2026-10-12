# encoding: UTF-8

# Specs must not depend on the blog address the local credentials hold, and
# CI has none; a spec can still stub its own.
RSpec.configure do |config|
  config.before do
    allow(Rails.application.credentials).to receive(:blog) { {url: "https://harshal-ladhe.vercel.app"} }
  end
end
