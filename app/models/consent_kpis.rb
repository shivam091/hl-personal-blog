# encoding: UTF-8

# Two site-wide consent figures for a period, set beside reports that rank by GA's numbers, so a fall in
# GA's share of readers isn't read as a fall in readers.
class ConsentKpis
  def initialize(period)
    @period = period
  end

  # From the nightly snapshots, so it matches what the consent report and morning check read; nil while too
  # few views are stored.
  def ga_share(within = @period)
    ConsentSnapshot.ga_share(within)
  end

  # Of the readers who answered the banner, every country together; nil under the per-country minimum,
  # since a handful of answers swings it as much as one country's would.
  def acceptance_rate(within = @period)
    granted = denied = 0
    ConsentChoice.within(within).each do |choice|
      choice.countries.each_value do |events|
        granted += events["granted"].to_i
        denied += events["denied"].to_i
      end
    end
    answered = granted + denied
    granted.fdiv(answered) if answered >= CountryBanners::MIN_ANSWERS_FOR_RATE
  end
end
