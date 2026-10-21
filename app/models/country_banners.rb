# encoding: UTF-8

# The banner's answers per country for a period, set beside the country report's other figures. Only readers
# in the EEA, UK and Switzerland are asked, so a country without a banner has no rate rather than a low one.
class CountryBanners
  # Below this many answers, one reader moves the rate by ten points or more.
  MIN_ANSWERS_FOR_RATE = 10

  Row = Struct.new(:shown, :granted, :denied, keyword_init: true) do
    def answered
      granted + denied
    end

    def acceptance_rate
      granted.fdiv(answered) if answered >= MIN_ANSWERS_FOR_RATE
    end
  end

  def initialize(period)
    @period = period
  end

  # Only the countries the banner was shown in, so every other country reads as not asked rather than as 0%.
  def rows
    @rows ||= ConsentChoice.within(@period).each_with_object({}) do |choice, totals|
      choice.countries.each do |code, events|
        row = totals[code] ||= Row.new(shown: 0, granted: 0, denied: 0)
        row.shown += events["shown"].to_i
        row.granted += events["granted"].to_i
        row.denied += events["denied"].to_i
      end
    end.select { |_code, row| row.shown.positive? }
  end

  def [](code)
    rows[code]
  end

  def shown(code)
    rows[code]&.shown
  end

  def acceptance_rate(code)
    rows[code]&.acceptance_rate
  end

  def any?
    rows.any?
  end
end
