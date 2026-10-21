# encoding: UTF-8

# Which days a source has figures for, so a day it's missing can be told from one before it was recorded
# at all, and, for a tally only written when something happens, from a day nothing did.
class DayCoverage
  attr_reader :name, :since

  # A tally names the day it began, nil if it hasn't yet; quiet names a day without figures on one that only
  # records what it finds, so that day isn't read as missing.
  def initialize(name, present, tally: false, since: nil, quiet: nil)
    @name = name
    @present = present.to_set
    @tally = tally
    @since = since
    @quiet = quiet
  end

  class << self
    # Each from the day it began, so days before a tally existed aren't read as missing.
    def tallies(period)
      [
        new("Consent split", days(PageView.consent_daily(period)), tally: true, since: PageView.consent_first_day),
        new("Tag loading", days(PageView.ga_daily(period)), tally: true, since: PageView.ga_first_day),
        new("Automation", days(PageView.suspect_daily(period)), tally: true, since: PageView.suspect_first_day, quiet: "Nothing flagged")
      ]
    end

    private

    # A day the frontend wrote oddly is left out rather than breaking the report.
    def days(by_day)
      by_day.keys.filter_map do |day|
        Date.iso8601(day)
      rescue Date::Error
        nil
      end
    end
  end

  def state(date)
    if @present.include?(date) then :present
    elsif @tally && (since.nil? || date < since) then :before
    elsif @quiet then :quiet
    else :missing
    end
  end

  def missing(dates)
    dates.count { |date| state(date) == :missing }
  end

  # False for a span wholly before the tally began, which has nothing to say about missing days.
  def recorded?(dates)
    dates.any? { |date| state(date) != :before }
  end

  # Nil when every day in the period could have been recorded, so a start date is only given when it explains a gap.
  def recorded_since(dates)
    since if since && dates.first && since > dates.first
  end

  def label(date)
    {present: "Has data", missing: "Missing", before: "Not recorded yet", quiet: @quiet}.fetch(state(date))
  end
end
