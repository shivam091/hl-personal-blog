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

    # A click counts though its open went unseen, as a mail app that blocks
    # images hides the open.
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

  # A mail sent before Brevo's webhook was set up has no events at all, and
  # would otherwise read as opened by no one.
  def rows
    @rows ||= begin
      readers = readers_by_tag(entries.map(&:url))
      entries.select { |entry| readers.key?(entry.url) }.map do |entry|
        by_event = readers[entry.url]
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

  # Rates over every mail of the period rather than the mean of each mail's,
  # so a mail to a handful doesn't weigh as much as one to the whole list;
  # nil without mail to judge them by.
  def rates
    base = rows.sum(&:base)
    return unless base.positive?

    {open_rate: rows.sum(&:opened).fdiv(base), click_rate: rows.sum(&:clicked).fdiv(base)}
  end

  def unreported_count
    entries.size - rows.size
  end

  def any_events?
    NewsletterEmailEvent.exists?
  end

  private

  def entries
    @entries ||= FeedEntry.where(notified_at: period.from.in_time_zone.beginning_of_day..period.to.in_time_zone.end_of_day)
      .order(notified_at: :desc).only(:_id, :name, :notified_at, :notified_count).to_a
  end

  def readers_by_tag(urls)
    return {} if urls.empty?

    NewsletterEmailEvent.where(:tag.in => urls).pluck(:tag, :event, :email).each_with_object({}) do |(tag, event, email), readers|
      ((readers[tag] ||= {})[event] ||= []) << email
    end
  end
end
