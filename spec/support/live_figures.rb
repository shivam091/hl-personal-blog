# encoding: UTF-8

# Reports ask GA for users and sessions as they load; specs never reach
# Google, so those fall back to the stored figures unless a spec says what
# GA returns.
RSpec.configure do |config|
  config.before(type: :request) do
    allow(Google::Analytics::LiveFigures).to receive(:call)
      .and_raise(Google::Analytics::LiveFigures::Unavailable, "not asked in specs")
  end
end
