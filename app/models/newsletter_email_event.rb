# encoding: UTF-8

# What Brevo saw happen to each mail after it left, kept here because
# Brevo's own logs only reach back a few weeks and can't be joined with the
# entry a mail announced.
class NewsletterEmailEvent
  include Mongoid::Document

  # Brevo sends more (requests, deferrals, proxy opens), none of which says
  # whether a reader got or read the mail.
  EVENTS = %w[delivered opened unique_opened click hard_bounce soft_bounce unsubscribed spam].freeze
  OPENS = %w[opened unique_opened].freeze
  BOUNCES = %w[hard_bounce soft_bounce].freeze

  field :event, type: String
  field :email, type: String
  field :message_id, type: String
  # The entry's URL the mail was tagged with when it was sent.
  field :tag, type: String
  field :link, type: String
  field :occurred_at, type: Time

  # Brevo retries a webhook it thinks failed, and every click on another
  # link in the same mail is an event of its own.
  index({message_id: 1, event: 1, link: 1}, {unique: true})
  index({tag: 1, event: 1})

  validates :event, inclusion: {in: EVENTS}
  validates :message_id, presence: true

  class << self
    # Inserted only if not already there, in one atomic upsert, so a retried
    # or doubled delivery from Brevo is stored once. Nil for an event that
    # isn't wanted or can't be told apart from another.
    def record(payload)
      event = new(
        event: payload["event"].to_s,
        email: payload["email"].to_s.downcase.presence,
        message_id: payload["message-id"].presence,
        tag: Array(payload["tags"]).first.presence || payload["tag"].presence,
        link: payload["link"].presence,
        occurred_at: occurred_at(payload)
      )
      return unless event.valid?

      key = event.attributes.slice("message_id", "event", "link")
      where(key).find_one_and_update(
        {"$setOnInsert" => event.attributes.except("_id")},
        upsert: true, return_document: :after
      )
    end

    private

    # Brevo's own epoch fields, in milliseconds and seconds, since its date
    # string has no time zone.
    def occurred_at(payload)
      if payload["ts_epoch"].present? then Time.zone.at(*payload["ts_epoch"].to_i.divmod(1000), :millisecond)
      elsif payload["ts_event"].present? then Time.zone.at(payload["ts_event"].to_i)
      elsif payload["ts"].present? then Time.zone.at(payload["ts"].to_i)
      else Time.current
      end
    end
  end
end
