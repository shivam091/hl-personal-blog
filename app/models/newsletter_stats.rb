# encoding: UTF-8

# The newsletter read as a whole, so whether entries bring readers onto the
# list, and whether the mail announcing them arrives, can be judged.
class NewsletterStats
  # A week either side of publishing, long enough for a reader to find an
  # entry and short enough that the next one rarely overlaps.
  SIGNUP_WINDOW = 7
  EXPORTS = {"entries" => "Sign-ups around each entry", "sends" => "Emails sent"}.freeze

  EntrySignups = Struct.new(:entry, :before, :after, :complete, keyword_init: true) do
    def change
      after - before
    end
  end
  Sends = Struct.new(:start, :sent, :undelivered, keyword_init: true)

  attr_reader :period, :country

  def initialize(period, country: nil, today: Date.current)
    @period = period
    @country = country
    @today = today
  end

  def list_size
    subscribers.count
  end

  def new_subscribers(within = period)
    subscribers(within.country || country).where(subscribed_at: span(within.from, within.to)).count
  end

  # Entries published in the period, newest first, each against the week
  # before it, so a jump in sign-ups can be put down to one entry.
  def signups_around_entries
    entries = FeedEntry.where(published_at: span(period.from, period.to)).order(published_at: :desc).only(:_id, :name, :published_at).to_a
    return [] if entries.empty?

    first = entries.last.published_at.to_date - SIGNUP_WINDOW
    last = entries.first.published_at.to_date + SIGNUP_WINDOW - 1
    days = subscribers.where(subscribed_at: span(first, last)).pluck(:subscribed_at).map { |time| time.in_time_zone.to_date }
    entries.map do |entry|
      published = entry.published_at.in_time_zone.to_date
      EntrySignups.new(
        entry: entry,
        before: days.count { |day| day >= published - SIGNUP_WINDOW && day < published },
        after: days.count { |day| day >= published && day < published + SIGNUP_WINDOW },
        complete: published + SIGNUP_WINDOW - 1 < @today
      )
    end
  end

  # By the week or month each entry was sent in, as delivery is judged per
  # send: weeks for a short period and months for a long one, as country
  # shares are, so there are enough bars without each being too thin.
  # Undelivered is what's still failed, since a resend that gets through
  # clears it. Not split by country, as a send goes to the whole list.
  def sends(within = period)
    by = sends_by(within)
    entries = FeedEntry.where(notified_at: span(within.from, within.to)).only(:notified_at, :notified_count, :notification_failures).to_a
    grouped = entries.group_by { |entry| bucket(entry.notified_at.in_time_zone.to_date, by) }
    (within.from..within.to).map { |date| bucket(date, by) }.uniq.map do |start|
      sent = grouped.fetch(start, [])
      Sends.new(start: start, sent: sent.sum { |entry| entry.notified_count.to_i }, undelivered: sent.sum { |entry| entry.notification_failures.size })
    end
  end

  def sends_by(within = period)
    within.days <= 120 ? :week : :month
  end

  # By the error's class, as its message usually names the address, which
  # would leave no two reasons alike.
  def failure_reasons
    FeedEntry.where("notification_failures.0" => {"$exists" => true}).only(:notification_failures)
      .flat_map(&:notification_failures).each_with_object(Hash.new(0)) do |failure, counts|
        counts[failure["error"].to_s.split(": ").first.presence || "Unknown"] += 1
      end
  end

  def to_csv(export = EXPORTS.keys.first)
    CSV.generate do |csv|
      case export
      when "sends"
        csv << ["#{sends_by.to_s.capitalize} starting", "Sent", "Undelivered"]
        sends.each { |row| csv << [row.start.iso8601, row.sent, row.undelivered] }
      else
        csv << ["URL", "Title", "Published", "Sign-ups week before", "Sign-ups week after", "Change", "Week after complete"]
        signups_around_entries.each do |row|
          csv << [row.entry.url, row.entry.name, row.entry.published_at.in_time_zone.to_date.iso8601, row.before, row.after, row.change,
            row.complete ? "Yes" : "No"]
        end
      end
    end
  end

  private

  # Coded as the blog's figures code countries, so a subscriber with none
  # counts under Unknown there and here alike.
  def subscribers(code = country)
    return NewsletterSubscriber.all unless code
    return NewsletterSubscriber.where(:country.not => /\A[A-Za-z]{2}\z/) if code == BlogStats::UNKNOWN_COUNTRY

    NewsletterSubscriber.where(country: /\A#{Regexp.escape(code)}\z/i)
  end

  def bucket(date, by)
    by == :week ? date.beginning_of_week : date.beginning_of_month
  end

  def span(from, to)
    from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
  end
end
