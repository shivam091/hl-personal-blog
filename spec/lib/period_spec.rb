# encoding: UTF-8

require "rails_helper"

RSpec.describe Period do
  let(:today) { Date.new(2026, 10, 12) }

  def period(params = {}, **options)
    described_class.new(ActionController::Parameters.new(params), today: today, **options)
  end

  it "covers the most recent full days when no dates are given, with no params in the URL" do
    expect([period.from, period.to, period.days]).to eq([Date.new(2026, 9, 14), Date.new(2026, 10, 11), 28])
    expect(period.query).to eq({})
    expect(period.preset?(28)).to be_truthy
  end

  it "reads dates from the URL, swapping them when typed the wrong way round" do
    custom = period({from: "2026-10-10", to: "2026-10-01"})

    expect([custom.from, custom.to]).to eq([Date.new(2026, 10, 1), Date.new(2026, 10, 10)])
    expect(custom.query).to eq(from: "2026-10-01", to: "2026-10-10")
  end

  it "ignores dates it can't read" do
    expect(period({from: "garbage", to: "2026-13-40"}).to).to eq(Date.new(2026, 10, 11))
  end

  it "offers the same number of days just before for comparison" do
    previous = period({from: "2026-10-01", to: "2026-10-10"}).previous

    expect([previous.from, previous.to]).to eq([Date.new(2026, 9, 21), Date.new(2026, 9, 30)])
  end

  it "compares a whole calendar month or year with the one before, however many days each has" do
    march = period({from: "2026-03-01", to: "2026-03-31"}).previous
    year = period({from: "2025-01-01", to: "2025-12-31"}).previous

    expect([march.from, march.to]).to eq([Date.new(2026, 2, 1), Date.new(2026, 2, 28)])
    expect([year.from, year.to]).to eq([Date.new(2024, 1, 1), Date.new(2024, 12, 31)])
  end

  it "links presets ending yesterday, leaving the default one out of the URL" do
    expect(period.preset_query(7)).to eq(from: "2026-10-05", to: "2026-10-11")
    expect(period.preset_query(28)).to eq({})
    expect(period(default_days: 90).preset_query(90)).to eq({})
  end

  it "offers yesterday as a day, compared with the day before" do
    day = period({from: "2026-10-11", to: "2026-10-11"})

    expect(period.preset_query(1)).to eq(from: "2026-10-11", to: "2026-10-11")
    expect(day.preset?(1)).to be_truthy
    expect([day.previous.from, day.previous.to]).to eq([Date.new(2026, 10, 10), Date.new(2026, 10, 10)])
    expect(Period::PRESETS.map { |preset| Period.preset_label(preset) })
      .to eq(["Today", "Yesterday", "7 days", "28 days", "This quarter", "Last quarter", "Last 3 months", "Last 6 months", "Last 8 months", "Last 12 months", "Last 16 months"])
  end

  it "offers today so far, compared with yesterday" do
    day = period(period.preset_query(:today))

    expect(period.preset_query(:today)).to eq(from: "2026-10-12", to: "2026-10-12")
    expect(day.preset?(:today)).to be_truthy
    expect(day.custom?).to be_falsy
    expect([day.previous.from, day.previous.to]).to eq([Date.new(2026, 10, 11), Date.new(2026, 10, 11)])
  end

  it "offers this quarter up to yesterday, and the last whole quarter compared with the one before it" do
    expect(period.preset_query(:this_quarter)).to eq(from: "2026-10-01", to: "2026-10-11")
    expect(period.preset_query(:last_quarter)).to eq(from: "2026-07-01", to: "2026-09-30")

    last = period(period.preset_query(:last_quarter))
    expect(last.preset?(:last_quarter)).to be_truthy
    expect([last.previous.from, last.previous.to]).to eq([Date.new(2026, 4, 1), Date.new(2026, 6, 30)])
    this = period(period.preset_query(:this_quarter))
    expect([this.previous.from, this.previous.to]).to eq([Date.new(2026, 9, 20), Date.new(2026, 9, 30)])
  end

  it "keeps this quarter on the one just ended on a quarter's first day, since it runs to yesterday" do
    first_day = period({}, today: Date.new(2026, 10, 1))

    expect(first_day.preset_query(:this_quarter)).to eq(from: "2026-07-01", to: "2026-09-30")
    expect(first_day.preset_query(:last_quarter)).to eq(from: "2026-04-01", to: "2026-06-30")
  end

  it "offers whole months back to the same day, ending yesterday" do
    expect(period.preset_query(:last_3_months)).to eq(from: "2026-07-12", to: "2026-10-11")
    expect(period.preset_query(:last_16_months)).to eq(from: "2025-06-12", to: "2026-10-11")

    six = period(period.preset_query(:last_6_months))
    expect([six.preset?(:last_6_months), six.custom?, six.preset]).to eq([true, false, :last_6_months])
    expect(period({from: "2026-10-01", to: "2026-10-05"}).preset).to be_nil
  end

  it "is custom only when no preset covers its dates" do
    expect(period.custom?).to be_falsy
    expect(period({from: "2026-07-01", to: "2026-09-30"}).custom?).to be_falsy
    expect(period({from: "2026-10-01", to: "2026-10-05"}).custom?).to be_truthy
  end

  it "compares with the same dates a year back when asked, keeping that choice in its links" do
    yearly = period({from: "2026-09-01", to: "2026-09-30", compare: "year"})

    expect([yearly.previous.from, yearly.previous.to]).to eq([Date.new(2025, 9, 1), Date.new(2025, 9, 30)])
    expect(yearly.query).to eq(from: "2026-09-01", to: "2026-09-30", compare: "year")
    expect(yearly.preset_query(28)).to eq(compare: "year")
    expect(yearly.preset_query(7)).to eq(from: "2026-10-05", to: "2026-10-11", compare: "year")
    expect(period({from: "2028-02-29", to: "2028-02-29", compare: "year"}).previous.from).to eq(Date.new(2027, 2, 28))
  end

  it "gives the dates another comparison would judge it against" do
    expect([period.previous_with("year").from, period.previous_with("year").to]).to eq([Date.new(2025, 9, 14), Date.new(2025, 10, 11)])
    expect(period({compare: "year"}).previous_with("previous").from).to eq(Date.new(2026, 8, 17))
  end

  it "compares with the period before unless turned off, keeping the default out of the URL" do
    expect(period.compare).to eq("previous")
    expect(period({compare: "decade"}).compare).to eq("previous")
    expect(period.query).to eq({})
    expect(period({compare: "previous"}).query).to eq({})
    expect([period.previous.from, period.previous.to]).to eq([Date.new(2026, 8, 17), Date.new(2026, 9, 13)])

    off = period({compare: "off"})
    expect(off.compare?).to be_falsy
    expect(off.query).to eq(compare: "off")
    expect(off.preset_query(7)).to eq(from: "2026-10-05", to: "2026-10-11", compare: "off")
  end

  it "names a single day by itself rather than as a range" do
    day = period({from: "2026-10-10", to: "2026-10-10"})

    expect(day.to_s).to eq(I18n.l(Date.new(2026, 10, 10)))
    expect(period({from: "2026-10-09", to: "2026-10-10"}).to_s).to eq("#{I18n.l(Date.new(2026, 10, 9))} – #{I18n.l(Date.new(2026, 10, 10))}")
  end

  it "compares with another country over the same dates, only where pages are split by country" do
    by_country = period({compare: "country", vs: "us"}, countries: true)

    expect(by_country.compare_countries?).to be_truthy
    expect(by_country.query).to eq(compare: "country", vs: "US")
    expect([by_country.previous.from, by_country.previous.to, by_country.previous.country]).to eq([by_country.from, by_country.to, "US"])
    expect(by_country.previous.to_s).to eq("US")
    expect(by_country.previous.key).not_to eq(by_country.key)

    expect(period({compare: "country", vs: "US"}).compare).to eq("previous")
    expect(period({compare: "country"}, countries: true).compare).to eq("previous")
    expect(period({compare: "previous", vs: "US"}, countries: true).query).to eq({})
  end

  it "still covers today when it's picked as a date" do
    expect(period({from: "2026-10-12", to: "2026-10-12"}).preset?(1)).to be_falsy
    expect(period({from: "2026-10-12", to: "2026-10-12"}).preset?(:today)).to be_truthy
    expect(period({from: "2026-10-06", to: "2026-10-12"}).to).to eq(today)
  end
end
