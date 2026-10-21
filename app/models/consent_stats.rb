# encoding: UTF-8

# The banner's answers beside the views GA misses, for one period, so how much of
# GA's shortfall is readers' own choice can be told from what isn't.
class ConsentStats
  # "pending" is a reader the banner was due to ask who hasn't answered, which GA can't see; "default" needs no
  # banner and is counted; "unset" is how views were recorded before the two were told apart.
  STATES = %w[granted denied pending default unset].freeze

  # "changed" is on top of the granted or denied it led to, so it is never added to
  # them as a fourth answer.
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

  # Whether the banner reaches the readers it should: views it was due on but never got an answer
  # for, and views with no country, which the frontend used to give no banner at all.
  BannerHealth = Struct.new(:shown, :pending_views, :views, :unknown_country_views, keyword_init: true) do
    # Each impression is one browser session, so a reader's pending views per impression show how many pages a
    # banner sat unanswered through; a figure that keeps climbing means the banner stopped appearing.
    def pending_per_banner
      pending_views.fdiv(shown) if shown.positive?
    end

    def unknown_country_share
      unknown_country_views.fdiv(views) if views.positive?
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

    # Capped at the gap, as declines can't account for more views than went
    # missing; the rest is blockers, bots and GA's own sampling.
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

  class << self
    # For a single day, so the snapshot job and the morning alerts work a day out as the report does;
    # GA's figure is nil on a day it hasn't synced.
    def inputs_for(date, today: Date.current)
      period = Period.new({from: date.iso8601, to: date.iso8601}, today: today)
      first_party = BlogStats.new(period).daily(:views).first.to_i
      analytics = Google::Analytics::Summary.new(period).daily_views.first
      new(period).inputs(date, first_party, analytics)
    end
  end

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

  # Nil without GA's figures, so the report can tell no comparison from an even
  # one; only days both sources know are set against each other.
  def gap(first_party, analytics)
    return unless analytics

    states = daily_states
    days = analytics.keys.sort.reverse.filter_map do |date|
      next unless states.key?(date.iso8601)

      Day.new(date: date, first_party: first_party.fetch(date, 0), analytics: analytics[date], denied: states[date.iso8601]["denied"].to_i)
    end
    Gap.new(days: days)
  end

  # Nil without GA's figures. A day already snapshotted is read from its snapshot, so GA revising its numbers later
  # doesn't rewrite it; other days are worked out now, as the snapshot job would.
  def decomposition(first_party, analytics)
    return unless analytics

    stored = ConsentSnapshot.stored(period)
    snapshots = analytics.keys.sort.reverse.map do |date|
      snapshot = stored[date.iso8601]
      snapshot&.analytics.nil? ? ConsentSnapshot.compose(inputs(date, first_party.fetch(date, 0), analytics[date])) : snapshot
    end
    ConsentGap.new(snapshots)
  end

  # Built in one place, so a live day and a stored snapshot are worked out from the same figures.
  def inputs(date, first_party, analytics)
    day = date.iso8601
    ConsentSnapshot::Inputs.new(
      date: date, first_party: first_party, analytics: analytics, states: daily_states[day], ga: ga_daily[day],
      suspects: suspect_daily[day], banner: banner_by_day[day]
    )
  end

  def ga_first_day
    PageView.ga_first_day
  end

  def suspects_first_day
    PageView.suspect_first_day
  end

  # Every country, as the views the banner is due on aren't split by one.
  def banner_health
    blog = BlogStats.new(period)
    by_country = blog.by_country(:views)
    BannerHealth.new(shown: ConsentChoice.within(period).sum { |choice| choice.countries.values.sum { |events| events["shown"].to_i } },
      pending_views: views_by_state["pending"], views: by_country.values.sum, unknown_country_views: by_country.fetch(BlogStats::UNKNOWN_COUNTRY, 0))
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

  def ga_daily
    @ga_daily ||= PageView.ga_daily(period)
  end

  def suspect_daily
    @suspect_daily ||= PageView.suspect_daily(period)
  end

  # Every country's together, by ISO day, since views aren't split by country either.
  def banner_by_day
    @banner_by_day ||= ConsentChoice.within(period).to_h do |choice|
      events = choice.countries.values.each_with_object(Hash.new(0)) { |counts, sums| counts.each { |event, count| sums[event] += count.to_i } }
      [choice.day, funnel("All", events)]
    end
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
