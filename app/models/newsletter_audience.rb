# encoding: UTF-8

# Where readers join the list from and how soon they leave it, so a form
# that brings in readers who stay can be told from one that brings in
# readers who don't.
class NewsletterAudience
  # Spans a reader thinks of a list in: a mistake, a first look, or a few
  # mails in.
  STAYED_BANDS = {
    "Within a day" => 0...1,
    "Within a week" => 1...7,
    "Within a month" => 7...30,
    "Within 3 months" => 30...91,
    "Later" => 91..
  }.freeze
  UNKNOWN_STAY = "Unknown"
  PAGES = 10

  attr_reader :period

  def initialize(period)
    @period = period
  end

  # Those who've left since are counted too, so a form whose readers soon
  # leave isn't made to look smaller than it was.
  def signups_by_source(within = period)
    signups(within).each_with_object(Hash.new(0)) do |(source, _), counts|
      counts[NewsletterSubscriber.source_label(source)] += 1
    end
  end

  def signups_by_page(within = period, limit: PAGES)
    signups(within).each_with_object(Hash.new(0)) { |(_, page), counts| counts[page.presence || "Unknown"] += 1 }
      .sort_by { |page, count| [-count, page] }.first(limit).to_h
  end

  def unsubscribes(within = period)
    NewsletterUnsubscribe.where(unsubscribed_at: span(within))
  end

  def unsubscribe_count(within = period)
    unsubscribes(within).count
  end

  # The blog only began keeping who left on some day; a period before it
  # would read as nobody leaving.
  def counted_since
    return @counted_since if defined?(@counted_since)

    @counted_since = NewsletterUnsubscribe.order(unsubscribedAt: :asc).only(:unsubscribedAt).first&.unsubscribed_at&.to_date
  end

  def counted?(within = period)
    counted_since.present? && within.from >= counted_since
  end

  # Of everyone on the list as the period began: those still on it who'd
  # joined by then, and those who've left since who had. Nil until leaving
  # was recorded from the period's start, as the list then can't be rebuilt.
  def churn_rate(within = period)
    return unless counted?(within)

    start = within.from.in_time_zone.beginning_of_day
    on_list = NewsletterSubscriber.where(:subscribed_at.lt => start).count +
      NewsletterUnsubscribe.where(:subscribed_at.lt => start, :unsubscribed_at.gte => start).count
    unsubscribe_count(within).fdiv(on_list) if on_list.positive?
  end

  def by_method
    unsubscribes.only(:method).each_with_object(Hash.new(0)) { |unsubscribe, counts| counts[unsubscribe.method_label] += 1 }
  end

  def stays
    days = unsubscribes.only(:subscribedAt, :unsubscribedAt).map(&:days_subscribed)
    STAYED_BANDS.transform_values { |range| days.count { |stayed| stayed && range.cover?(stayed) } }
      .merge(UNKNOWN_STAY => days.count(&:nil?))
  end

  # Halfway between the middle two of an even count, as the other medians are.
  def median_days_subscribed
    days = unsubscribes.only(:subscribedAt, :unsubscribedAt).filter_map(&:days_subscribed).sort
    ((days[(days.size - 1) / 2] + days[days.size / 2]) / 2.0).round if days.any?
  end

  # Weeks start on Monday, as the blog's do; a week cut by the period's
  # edge counts only its days in it.
  def weekly_unsubscribes
    counts = unsubscribes.pluck(:unsubscribedAt).map { |time| time.in_time_zone.to_date.beginning_of_week }.tally
    (period.from.beginning_of_week..period.to).step(7).map { |week| [week, counts.fetch(week, 0)] }
  end

  private

  def signups(within)
    NewsletterSubscriber.where(subscribed_at: span(within)).pluck(:source, :sourcePage) +
      NewsletterUnsubscribe.where(subscribed_at: span(within)).pluck(:source, :sourcePage)
  end

  def span(within)
    within.from.in_time_zone.beginning_of_day..within.to.in_time_zone.end_of_day
  end
end
