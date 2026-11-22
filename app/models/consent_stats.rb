# encoding: UTF-8

# What readers answered the consent banner, and how many page views that
# leaves out of GA, for a period.
class ConsentStats
  STATES = %w[granted denied unset].freeze

  # Banner events for one country; "changed" counts readers flipping an
  # earlier answer, on top of the granted or denied it led to.
  Funnel = Struct.new(:country, :shown, :granted, :denied, :changed, keyword_init: true) do
    def answered
      granted + denied
    end

    # Floored, as an answer given through the privacy policy needs no banner.
    def no_answer
      [shown - answered, 0].max
    end

    def acceptance_rate
      granted.fdiv(answered) if answered.positive?
    end
  end

  Day = Struct.new(:date, :first_party, :analytics, :denied, keyword_init: true)

  # Days both sources cover, so a day GA hasn't synced doesn't read as a gap.
  Gap = Struct.new(:days, keyword_init: true) do
    def first_party
      days.sum(&:first_party)
    end

    def analytics
      days.sum(&:analytics)
    end

    def denied
      days.sum(&:denied)
    end

    def difference
      first_party - analytics
    end

    def percent
      difference.fdiv(first_party) if first_party.positive?
    end

    # What declining readers account for at most; the rest is blockers, bots
    # and GA's own sampling.
    def explained
      difference.positive? ? [denied, difference].min : 0
    end

    def unexplained
      [difference - explained, 0].max
    end

    def explained_share
      explained.fdiv(difference) if difference.positive?
    end
  end

  attr_reader :period, :country

  def initialize(period, country: nil)
    @period = period
    @country = country
  end

  # Busiest banner first, so the countries that matter lead.
  def countries
    rows = totals_by_country.map { |code, events| funnel(code, events) }
    rows.select! { |row| row.country == country } if country
    rows.sort_by { |row| [-row.shown, row.country] }
  end

  def total
    funnel("All", countries.each_with_object(Hash.new(0)) { |row, sums| row.to_h.except(:country).each { |event, count| sums[event.to_s] += count } })
  end

  def any?
    ConsentChoice.within(period).exists?
  end

  def recording_since
    ConsentChoice.first_day
  end

  # Views by the reader's consent state, every country, since the frontend
  # doesn't split them by country.
  def views_by_state
    daily_states.values.each_with_object(Hash.new(0)) { |states, sums| states.each { |state, count| sums[state] += count } }
  end

  def tracked_views
    views_by_state.values.sum
  end

  def denied_share
    views_by_state["denied"].fdiv(tracked_views) if tracked_views.positive?
  end

  def views_tracked_since
    PageView.consent_first_day
  end

  # Nil without GA's figures; otherwise first-party views set against GA's on
  # the days both are known, newest first.
  def gap(first_party, analytics)
    return unless analytics

    states = daily_states
    days = analytics.keys.sort.reverse.filter_map do |date|
      next unless states.key?(date.iso8601)

      Day.new(date: date, first_party: first_party.fetch(date, 0), analytics: analytics[date], denied: states[date.iso8601]["denied"].to_i)
    end
    Gap.new(days: days)
  end

  def to_csv
    CSV.generate do |csv|
      csv << ["Country", "Banner shown", "Accepted", "Declined", "No answer", "Changed mind", "Acceptance rate"]
      (countries + [total]).each do |row|
        csv << [row.country, row.shown, row.granted, row.denied, row.no_answer, row.changed, row.acceptance_rate&.round(4)]
      end
    end
  end

  private

  def daily_states
    @daily_states ||= PageView.consent_daily(period)
  end

  def totals_by_country
    ConsentChoice.within(period).each_with_object(Hash.new { |hash, code| hash[code] = Hash.new(0) }) do |choice, totals|
      choice.countries.each do |code, events|
        events.each { |event, count| totals[code][event] += count.to_i }
      end
    end
  end

  def funnel(code, events)
    Funnel.new(country: code, shown: events["shown"].to_i, granted: events["granted"].to_i, denied: events["denied"].to_i, changed: events["changed"].to_i)
  end
end
