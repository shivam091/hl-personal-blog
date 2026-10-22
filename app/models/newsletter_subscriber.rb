# encoding: UTF-8

require "csv"

class NewsletterSubscriber
  include Mongoid::Document

  CSV_HEADERS = ["Email", "Country", "Subscribed"].freeze
  # The blog's form ids, named as a reader would see the form.
  SOURCES = {"footer" => "Footer", "article_end" => "End of an article", "article_inline" => "Within an article"}.freeze

  field :email, type: String
  field :country, type: String
  field :subscribedAt, type: Time, as: :subscribed_at
  # Sign-ups from before the blog recorded which form they came through
  # have neither.
  field :source, type: String
  field :sourcePage, type: String, as: :source_page

  validates :email, presence: true

  # People type their address in different cases on different forms.
  scope :with_email, ->(email) { where(email: /\A#{Regexp.escape(email.to_s)}\z/i) }

  def source_label
    self.class.source_label(source)
  end

  def messages
    Message.with_email(email).order(created_at: :desc)
  end

  # Signed rather than the bare id, so one subscriber's link can't be turned
  # into another's. A plain HMAC with a secret of its own rather than Rails'
  # message verifier, so the blog's unsubscribe page can check it without
  # being given secret_key_base. No expiry, since a link in an old email
  # must still work.
  def unsubscribe_token
    "#{id}.#{self.class.unsubscribe_signature(id.to_s)}"
  end

  class << self
    # A form the blog adds later still shows, by its id, before it's named here.
    def source_label(source)
      SOURCES.fetch(source.to_s) { source.presence || "Unknown" }
    end

    # Blank countries counted under the blog's unknown code, so they're
    # listed apart from the map rather than lost.
    def country_counts(scope)
      scope.only(:country).each_with_object(Hash.new(0)) do |subscriber, counts|
        counts[subscriber.country.presence&.upcase || BlogStats::UNKNOWN_COUNTRY] += 1
      end
    end

    # The list's size at the end of each week from the first sign-up, so
    # its whole history reads as one line; weeks start on Monday, as the
    # blog's do.
    def weekly_totals(scope, today: Date.current)
      days = scope.only(:subscribedAt).filter_map do |subscriber|
        subscriber.subscribed_at&.to_date
      end.sort
      return {} if days.empty?

      total = 0
      by_week = days.group_by(&:beginning_of_week).transform_values(&:size)
      (days.first.beginning_of_week..today).step(7).to_h do |week|
        [week, total += by_week.fetch(week, 0)]
      end
    end

    # Prefixed, so a signature made for this can't be passed off as one for
    # anything else signed with the same secret. Kept identical to the
    # frontend's src/lib/mail/unsubscribe.ts, which refuses any link whose
    # signature differs.
    def unsubscribe_signature(id)
      OpenSSL::HMAC.hexdigest("SHA256", unsubscribe_secret, "unsubscribe:#{id}")
    end

    # Fails loudly, since without it every link would be refused.
    def unsubscribe_secret
      Rails.application.credentials.dig(:mailer, :unsubscribe_secret).presence ||
        raise(KeyError, "No unsubscribe secret configured (credentials mailer.unsubscribe_secret)")
    end

    # Lets the list be taken to a mailing tool or spreadsheet.
    def to_csv(subscribers = order(subscribed_at: :desc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        subscribers.each do |subscriber|
          csv << [subscriber.email, subscriber.country, subscriber.subscribed_at&.utc&.iso8601(3)]
        end
      end
    end
  end
end
