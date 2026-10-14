# encoding: UTF-8

require "csv"

# A copy of the blog's Atom feed, so what's been published can be searched
# by type, tag, and category without reading the XML. The feed is the source
# of truth, so entries change only by syncing or importing, never by hand.
class FeedEntry
  include Mongoid::Document
  include Mongoid::Timestamps
  include StripAttribute

  TYPES = %w[post tutorial snippet].freeze
  CSV_HEADERS = ["#", "URL", "Title", "Description", "Type", "Published", "Updated", "Tags", "Categories"].freeze
  # Commas rather than another character, so the cell reads naturally in a
  # spreadsheet; no tag or category on the blog contains one.
  NAME_SEPARATOR = ","
  MAX_URL_LENGTH = 2048
  NOTIFY_DAYS = 3
  # Keyed on the entry's Atom id, which is its URL, so a sync can never
  # store the same entry twice.
  field :_id, type: String, overwrite: true, default: nil
  alias_attribute :url, :_id
  field :name, type: String
  field :description, type: String
  field :type, type: String
  field :published_at, type: Time
  field :last_modified_at, type: Time
  # Kept, so no one is told about the same entry twice. The count stays
  # empty until sending finishes, so the list can say it's still going out
  # rather than show a count that's still growing.
  field :notified_at, type: Time
  field :notified_count, type: Integer
  # So a bounced address or a broken mail setup can be seen without the logs,
  # which Render keeps only briefly.
  field :notification_failures, type: Array, default: -> { [] }

  # One-sided, so syncing an entry never has to rewrite every tag it uses.
  has_and_belongs_to_many :tags, inverse_of: nil, index: true
  has_and_belongs_to_many :categories, inverse_of: nil, index: true

  index({type: 1})
  # Sorts carry an _id tiebreaker, which an index without it can't serve.
  index({published_at: -1, _id: 1})
  index({last_modified_at: -1})

  strip_attributes! :_id, :name, :type

  validates :url, presence: true, length: {maximum: MAX_URL_LENGTH}
  validate :url_must_be_http
  validates :name, :published_at, :last_modified_at, presence: true
  validates :type, inclusion: {in: TYPES, message: "must be one of #{TYPES.join(", ")}"}

  # One shape for an entry whether it came from the feed or a CSV, so both
  # are saved, and report their outcome, the same way. `label` is kept so
  # an error points at the line or URL to fix.
  Source = Struct.new(:label, :url, :name, :description, :type, :published_at, :last_modified_at, :tags, :categories, keyword_init: true)

  def to_s
    url
  end

  # In the feed's order rather than the database's, so an export imports
  # back unchanged.
  def tag_names
    names_in_order(tags, tag_ids)
  end

  def category_names
    names_in_order(categories, category_ids)
  end

  class << self
    # Bad entries are reported rather than aborting, so one broken entry
    # doesn't keep the rest of the feed out.
    def import(sources, result = SyncResult.empty)
      # One query each up front instead of one per entry.
      tag_ids = Tag.ids_by_name(sources.flat_map(&:tags), result.errors)
      category_ids = Category.ids_by_name(sources.flat_map(&:categories), result.errors)
      entries = where(:_id.in => sources.map(&:url)).index_by(&:url)

      sources.each do |source|
        entry = entries[source.url] || new(url: source.url)
        entry.assign_attributes(
          name: source.name,
          description: source.description,
          type: source.type,
          published_at: source.published_at,
          last_modified_at: source.last_modified_at,
          tag_ids: source.tags.filter_map { |name| tag_ids[name.to_s.strip] }.uniq,
          category_ids: source.categories.filter_map { |name| category_ids[name.to_s.strip] }.uniq
        )
        save_entry(entry, source.label, result)
        # A source listing the same URL twice updates it the second time
        # rather than failing as a duplicate.
        entries[entry.url] = entry if entry.persisted?
      end

      result
    end

    # Same columns to_csv writes, so an export can be edited and imported
    # back.
    def import_csv(source)
      result = SyncResult.empty
      sources = []
      csv = CSV.new(source, headers: true, header_converters: ->(h) { h.to_s.delete_prefix("﻿").strip })

      csv.each.with_index(2) do |row, line| # line 1 is the header
        unless row.headers.include?("URL")
          result.errors << "Line 1: missing a URL column (expected #{CSV_HEADERS.join(",")})"
          break
        end

        sources << Source.new(
          label: "Line #{line}",
          url: row["URL"].to_s.strip,
          name: row["Title"],
          description: row["Description"],
          type: row["Type"].to_s.strip.downcase,
          published_at: parse_time(row["Published"], "Published"),
          last_modified_at: parse_time(row["Updated"], "Updated"),
          tags: split_names(row["Tags"]),
          categories: split_names(row["Categories"])
        )
      rescue ArgumentError => e
        result.errors << "Line #{line}: #{e.message}"
      end

      import(sources, result)
    rescue CSV::MalformedCSVError => e
      result.errors << e.message
      result
    end

    def to_csv(entries = order(published_at: :desc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        entries.includes(:tags, :categories).each.with_index(1) do |entry, number|
          csv << [
            number,
            entry.url,
            entry.name,
            entry.description,
            entry.type,
            entry.published_at&.utc&.iso8601(3),
            entry.last_modified_at&.utc&.iso8601(3),
            entry.tag_names.join("#{NAME_SEPARATOR} "),
            entry.category_names.join("#{NAME_SEPARATOR} ")
          ]
        end
      end
    end

    # Oldest first, so the chart reads left to right like a timeline. Only
    # sends that finished, since a count still going out isn't one yet.
    def recently_notified(scope, limit: 12)
      scope.where(:notified_at.ne => nil, :notified_count.ne => nil).order(notified_at: :desc).limit(limit)
        .only(:_id, :name, :notified_at, :notified_count, :notification_failures).to_a.reverse
    end

    private

    def save_entry(entry, label, result)
      return result.unchanged += 1 unless entry.new_record? || entry.changed?

      outcome = entry.new_record? ? :created : :updated
      if entry.save
        result[outcome] += 1
      else
        result.errors << "#{label}: #{entry.errors.full_messages.to_sentence}"
      end
    end

    # Truncated to the millisecond MongoDB stores, so an unchanged date
    # isn't seen as an update.
    def parse_time(value, column)
      value.presence && Time.iso8601(value.strip).floor(3)
    rescue ArgumentError
      raise ArgumentError, "invalid #{column} #{value.inspect} (expected ISO 8601, e.g. 2026-07-05T12:07:01.000Z)"
    end

    def split_names(value)
      value.to_s.split(NAME_SEPARATOR).map(&:strip).compact_blank
    end
  end

  # Only in the first few days after it was published, counted in the blog's
  # time zone, so subscribers hear about a post while it's news, and an old
  # one, like any a CSV import brings in, is never announced as new.
  def notifiable?
    notified_at.nil? && published_at.present? && published_at.in_time_zone.to_date > NOTIFY_DAYS.days.ago.to_date
  end

  # Claimed in one atomic update, so two clicks can't both mail everyone.
  def claim_notification!
    return false unless notifiable?

    claimed = self.class.where(_id: url, notified_at: nil).find_one_and_update({"$set" => {notified_at: Time.current}}, return_document: :after)
    claimed ? (self.notified_at = claimed.notified_at) && true : false
  end

  # One bad address mustn't keep the rest from hearing about the entry.
  # When none got through, the fault is likely the mail setup, so the entry
  # is left to be sent again once that's fixed.
  def notify_subscribers
    sent, failures = deliver_new_entry(NewsletterSubscriber.order(subscribed_at: :asc))
    set(notification_failures: failures)
    sent.zero? && NewsletterSubscriber.exists? ? unset(:notified_at) : set(notified_count: sent)
    sent
  end

  # Once a send has finished, and not while the entry can still be sent to
  # everyone, which would reach these addresses anyway. Unlike the first
  # send, any day, since the others have already heard about it.
  def resendable?
    notification_failures.present? && !notifiable? && (notified_at.nil? || notified_count.present?)
  end

  # Taken in one atomic update, like the first send, so two clicks can't
  # mail the same people twice.
  def claim_resend!
    return [] unless resendable?

    claimed = self.class.where(:_id => url, "notification_failures.0" => {"$exists" => true})
      .find_one_and_update({"$set" => {notification_failures: []}}, return_document: :before)
    self.notification_failures = []
    claimed ? claimed.notification_failures.map { |failure| failure["email"] } : []
  end

  # Only to those still subscribed, so no one who has left since is mailed.
  # Whoever fails again is kept, ready for another try.
  def resend_to(emails)
    sent, failures = deliver_new_entry(NewsletterSubscriber.where(:email.in => emails).order(subscribed_at: :asc))
    set(notification_failures: failures)
    set(notified_at: notified_at || Time.current, notified_count: notified_count.to_i + sent) if sent.positive?
    sent
  end

  private

  # One bad address mustn't keep the rest from hearing about the entry, so
  # each failure is kept with its reason instead of stopping the send.
  def deliver_new_entry(subscribers)
    failures = []
    sent = subscribers.count do |subscriber|
      NewsletterMailer.new_entry(self, subscriber).message
      true
    rescue => e
      Rails.logger.warn("New entry mail to #{subscriber.email}: #{e.message}")
      failures << {"email" => subscriber.email, "error" => "#{e.class}: #{e.message}", "failed_at" => Time.current}
      false
    end
    [sent, failures]
  end

  def names_in_order(records, ids)
    records.index_by(&:id).values_at(*ids).compact.map(&:name)
  end

  def url_must_be_http
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError # includes URLs containing whitespace
    errors.add(:url, "must be an http(s) URL")
  end
end
