# encoding: UTF-8

require "rails_helper"

RSpec.describe Google::PageSpeed::ResultHistory do
  def run(url, performance, days_ago, strategy: "mobile")
    described_class.create!(url: url, page_path: URI.parse(url).path, strategy: strategy, performance: performance, fetched_at: days_ago.days.ago)
  end

  it "lists pages whose latest score fell at least ten points from the run before, worst drop first" do
    run("https://blog.example.com/post/a", 0.95, 9)
    run("https://blog.example.com/post/a", 0.7, 2)
    run("https://blog.example.com/post/b", 0.9, 9)
    run("https://blog.example.com/post/b", 0.8, 2)
    run("https://blog.example.com/post/c", 0.9, 9)
    run("https://blog.example.com/post/c", 0.85, 2)
    run("https://blog.example.com/post/d", 0.5, 9)
    run("https://blog.example.com/post/d", 0.9, 2)
    described_class.create!(url: "https://blog.example.com/post/b", strategy: "mobile", fetched_at: 1.day.ago, error: "Timed out")

    rows = described_class.regressions
    expect(rows.map { |row| [row.page_path, row.drop.round(2)] }).to eq([["/post/a", 0.25], ["/post/b", 0.1]])
  end

  it "marks a run as regressed only against an earlier scored one" do
    before, after = run("https://blog.example.com/", 0.9, 2), run("https://blog.example.com/", 0.75, 1)

    expect(after.regressed_from?(before)).to be(true)
    expect(after.regressed_from?(nil)).to be(false)
    expect(before.regressed_from?(after)).to be(false)
  end
end
