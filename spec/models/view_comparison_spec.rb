# encoding: UTF-8

require "rails_helper"

RSpec.describe ViewComparison do
  let(:today) { Date.new(2026, 10, 12) }
  let(:period) { Period.new({from: "2026-10-06", to: "2026-10-12"}, today: today) }

  def blog(path, views)
    PageView.collection.insert_one("_id" => path, "slug" => path, "countriesByDay" => {"2026-10-09" => {"IN" => views}})
  end

  def ga(path, views)
    Google::Analytics::Stat.create!(date: Date.new(2026, 10, 9), page_path: path, views: views)
  end

  before do
    blog("/post/a", 100)
    ga("/post/a", 80)
    ga("/post/ga-only", 50)
    blog("/post/b", 40)
    ga("/post/b", 40)
    blog("/post/blog-only", 40)
    blog("/post/c", 3)
    ga("/post/c", 1)
  end

  subject(:comparison) { described_class.new(BlogStats.new(period), Google::Analytics::Summary.new(period)) }

  it "lists every page either side counted, busiest first, then by path" do
    expect(comparison.rows.map(&:first)).to eq([
      "/post/a", "/post/ga-only", "/post/b", "/post/blog-only", "/post/c"
    ])
  end

  it "gives GA's difference as a share of the blog's count, leaving it blank when the blog saw nothing" do
    differences = comparison.rows.to_h { |path, *, difference| [path, difference] }

    expect(differences).to include(
      "/post/a" => be_within(0.0001).of(-0.2),
      "/post/b" => 0.0,
      "/post/blog-only" => -1.0,
      "/post/ga-only" => nil
    )
  end

  it "exports the rows with the difference rounded" do
    rows = CSV.parse(comparison.to_csv)

    expect(rows.first).to eq(described_class::CSV_HEADERS)
    expect(rows.find { |row| row.first == "/post/c" }).to eq(["/post/c", "3", "1", "-0.6667"])
    expect(rows.find { |row| row.first == "/post/ga-only" }).to eq(["/post/ga-only", "0", "50", nil])
  end
end
