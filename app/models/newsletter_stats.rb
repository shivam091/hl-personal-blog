# encoding: UTF-8

# The newsletter read as a whole, so whether entries bring readers onto the
# list, and whether the mail announcing them arrives, can be judged.
class NewsletterStats
  # A week either side of publishing, long enough for a reader to find an
  # entry and short enough that the next one rarely overlaps.
  SIGNUP_WINDOW = 7
  SEND_MONTHS = 12

  EntrySignups = Struct.new(:entry, :before, :after, :complete, keyword_init: true) do
    def change
      after - before
    end
  end
  SendMonth = Struct.new(:month, :sent, :undelivered, keyword_init: true)

  attr_reader :period

  def initialize(period, today: Date.current)
    @period = period
    @today = today
  end

  def list_size
    NewsletterSubscriber.count
  end

  def new_subscribers(within = period)
    NewsletterSubscriber.where(subscribed_at: span(within.from, within.to)).count
  end

  # Entries published in the period, newest first, each against the week
  # before it, so a jump in sign-ups can be put down to one entry.
  def signups_around_entries
    entries = FeedEntry.where(published_at: span(period.from, period.to)).order(published_at: :desc).only(:_id, :name, :published_at).to_a
    return [] if entries.empty?

    first = entries.last.published_at.to_date - SIGNUP_WINDOW
    last = entries.first.published_at.to_date + SIGNUP_WINDOW - 1
    days = NewsletterSubscriber.where(subscribed_at: span(first, last)).pluck(:subscribed_at).map { |time| time.in_time_zone.to_date }
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

  # By the month each entry was sent, as delivery is judged per send.
  # Undelivered is what's still failed, since a resend that gets through
  # clears it.
  def sends
    months = (0...SEND_MONTHS).map { |back| (@today << back).beginning_of_month }.reverse
    entries = FeedEntry.where(:notified_at.gte => months.first.in_time_zone.beginning_of_day)
      .only(:notified_at, :notified_count, :notification_failures).to_a
    by_month = entries.group_by { |entry| entry.notified_at.in_time_zone.to_date.beginning_of_month }
    months.map do |month|
      sent = by_month.fetch(month, [])
      SendMonth.new(month: month, sent: sent.sum { |entry| entry.notified_count.to_i },
        undelivered: sent.sum { |entry| entry.notification_failures.size })
    end
  end

  def undelivered
    FeedEntry.where("notification_failures.0" => {"$exists" => true}).only(:notification_failures).sum { |entry| entry.notification_failures.size }
  end

  # By the error's class, as its message usually names the address, which
  # would leave no two reasons alike.
  def failure_reasons
    FeedEntry.where("notification_failures.0" => {"$exists" => true}).only(:notification_failures)
      .flat_map(&:notification_failures).each_with_object(Hash.new(0)) do |failure, counts|
        counts[failure["error"].to_s.split(": ").first.presence || "Unknown"] += 1
      end
  end

  private

  def span(from, to)
    from.in_time_zone.beginning_of_day..to.in_time_zone.end_of_day
  end
end
