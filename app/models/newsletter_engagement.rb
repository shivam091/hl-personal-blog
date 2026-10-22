# encoding: UTF-8

# Each new-entry mail's opens and clicks, from the events Brevo posts back,
# so which entries readers act on is known per send rather than guessed
# from the blog's traffic.
class NewsletterEngagement
  # Counted per reader, so one reader opening a mail five times is one open.
  Row = Struct.new(:entry, :sent, :delivered, :opened, :clicked, :bounced, :unsubscribed, :spam, keyword_init: true) do
    def open_rate
      opened.fdiv(base) if base.positive?
    end

    def click_rate
      clicked.fdiv(base) if base.positive?
    end

    # Delivered once Brevo reports deliveries, so a rate isn't of mails that
    # never arrived; what was sent until then.
    def base
      delivered.positive? ? delivered : sent.to_i
    end

    # Every mail split the four ways of PARTS, so one bar per entry shows how
    # far its readers got. A click counts though its open went unseen, as a
    # mail app that blocks images hides the open.
    def parts
      reached = delivered.positive? ? delivered : [sent.to_i - bounced, 0].max
      clicks = [clicked, reached].min
      opens = [[opened - clicked, 0].max, reached - clicks].min
      [clicks, opens, reached - clicks - opens, bounced]
    end
  end

  PARTS = ["Clicked", "Opened, no click", "Not opened", "Bounced"].freeze

  attr_reader :period

  def initialize(period)
    @period = period
  end

  # Entries whose mail went out in the period, newest first.
  def rows
    @rows ||= begin
      entries = FeedEntry.where(notified_at: period.from.in_time_zone.beginning_of_day..period.to.in_time_zone.end_of_day)
        .order(notified_at: :desc).only(:_id, :name, :notified_at, :notified_count).to_a
      readers = readers_by_tag(entries.map(&:url))
      entries.map do |entry|
        by_event = readers.fetch(entry.url, {})
        count = ->(*events) { events.flat_map { |event| by_event.fetch(event, []) }.uniq.size }
        Row.new(
          entry: entry,
          sent: entry.notified_count,
          delivered: count.("delivered"),
          opened: count.(*NewsletterEmailEvent::OPENS),
          clicked: count.("click"),
          bounced: count.(*NewsletterEmailEvent::BOUNCES),
          unsubscribed: count.("unsubscribed"),
          spam: count.("spam")
        )
      end
    end
  end

  def any_events?
    NewsletterEmailEvent.exists?
  end

  private

  def readers_by_tag(urls)
    return {} if urls.empty?

    NewsletterEmailEvent.where(:tag.in => urls).pluck(:tag, :event, :email).each_with_object({}) do |(tag, event, email), readers|
      ((readers[tag] ||= {})[event] ||= []) << email
    end
  end
end
