# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::Analytics::AiAssistants do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({from: "2026-10-05", to: "2026-10-11"}, today: today) }

  def landing(date, source, sessions, page_path: "/post/a", engaged: 0, key_events: 0)
    Google::Analytics::LandingSourceStat.create!(date: date, page_path: page_path, channel_group: "Referral", source: source,
      medium: "referral", sessions: sessions, engaged_sessions: engaged, key_events: key_events)
  end

  def synced(date)
    Google::Analytics::Stat.create!(date: date, page_path: "/post/a", views: 1)
  end

  it "tells each assistant by its host, any subdomain of it, or its utm_source tag" do
    expect(described_class.assistant("chatgpt.com")).to eq("ChatGPT")
    expect(described_class.assistant("chat.openai.com")).to eq("ChatGPT")
    expect(described_class.assistant("ChatGPT")).to eq("ChatGPT")
    expect(described_class.assistant("www.perplexity.ai")).to eq("Perplexity")
    expect(described_class.assistant("gemini.google.com")).to eq("Gemini")
    expect(described_class.assistant("claude.ai")).to eq("Claude")
    expect(described_class.assistant("google")).to be_nil
    expect(described_class.assistant("notchatgpt.com")).to be_nil
    expect(described_class.assistant("chatgpt.com.example.org")).to be_nil
  end

  it "adds up the assistants' visits by day, assistant and landing page, leaving other sources out" do
    synced(Date.new(2026, 10, 5))
    synced(Date.new(2026, 10, 6))
    landing(Date.new(2026, 10, 5), "chatgpt.com", 3, engaged: 2, key_events: 1)
    landing(Date.new(2026, 10, 5), "chat.openai.com", 1, page_path: "/post/b", engaged: 1)
    landing(Date.new(2026, 10, 6), "perplexity.ai", 2)
    landing(Date.new(2026, 10, 6), "google", 50)
    landing(Date.new(2026, 10, 1), "chatgpt.com", 9)

    assistants = described_class.new(period)

    expect(assistants.totals.to_a).to eq([6, 3, 1])
    expect(assistants.totals.engagement_rate).to eq(0.5)
    expect(assistants.daily).to eq([4, 2, nil, nil, nil, nil, nil])
    expect(assistants.by_assistant.map { |name, figures| [name, figures.sessions] }).to eq([["ChatGPT", 4], ["Perplexity", 2]])
    expect(assistants.pages).to eq("/post/a" => 5, "/post/b" => 1)
  end

  it "has no earlier figures before GA was first synced, so the first week can't read as a jump" do
    synced(Date.new(2026, 10, 5))
    landing(Date.new(2026, 10, 5), "chatgpt.com", 3)

    expect(described_class.new(period).previous_totals).to be_nil

    synced(Date.new(2026, 9, 28))
    expect(described_class.new(period).previous_totals.sessions).to eq(0)
  end
end
