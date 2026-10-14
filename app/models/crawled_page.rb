# encoding: UTF-8

require "csv"

# Tracks which blog pages Google has indexed so gaps in search coverage
# can be spotted and followed up. CSV import/export exists so the data can
# round-trip with the crawl report it comes from.
class CrawledPage
  include Mongoid::Document
  include Mongoid::Timestamps
  include StripAttribute

  CSV_HEADERS = ["#", "URL", "Last modified", "Status"].freeze

  field :url, type: String
  field :last_modified_at, type: Time
  field :indexed, type: Boolean, default: false
  # Set on asking Google to index the page and cleared once an inspection
  # finds it indexed, so a request is followed until it lands.
  field :index_requested_at, type: Time

  has_one :url_inspection, class_name: "Google::SearchConsole::UrlInspection", dependent: :destroy

  index({url: 1}, {unique: true})
  # So unindexed pages can be listed newest first, and queued for inspection
  # oldest request first, without a scan.
  index({indexed: 1, last_modified_at: -1})
  index({indexed: 1, index_requested_at: 1})

  MAX_URL_LENGTH = 2048

  strip_attributes! :url

  validates :url, presence: true, uniqueness: true, length: {maximum: MAX_URL_LENGTH}
  validate :url_must_be_http
  validate :last_modified_at_must_be_valid_past_time
  # Mongoid turns unreadable input ("maybe") into nil, which must not pass
  # silently as "not indexed".
  validates :indexed, inclusion: {in: [true, false], message: "must be yes or no"}

  scope :indexed, -> { where(indexed: true) }
  scope :not_indexed, -> { where(indexed: false) }
  scope :index_requested, -> { not_indexed.where(:index_requested_at.ne => nil) }

  def to_s
    url
  end

  # A concurrent save of the same URL can slip past the uniqueness
  # validation; it should surface as a form error, not a crash.
  def save(...)
    super
  rescue Mongo::Error::OperationFailure => e
    raise unless e.code == 11000 # duplicate key

    errors.add(:url, :taken)
    false
  end

  class << self
    # Bad rows are reported rather than aborting, so one typo doesn't block
    # the rest of the file.
    def import_csv(source)
      result = SyncResult.empty
      csv = CSV.new(source, headers: true, header_converters: ->(h) { h.to_s.delete_prefix("﻿").strip })

      csv.each.with_index(2) do |row, line| # line 1 is the header
        unless row.headers.include?("URL")
          result.errors << "Line 1: missing a URL column (expected #{CSV_HEADERS.join(",")})"
          break
        end

        page = find_or_initialize_by(url: row["URL"].to_s.strip)
        page.assign_attributes(last_modified_at: parse_time(row["Last modified"]), indexed: indexed_status?(row["Status"]))

        if page.new_record? || page.changed?
          outcome = page.new_record? ? :created : :updated
          if page.save
            result[outcome] += 1
          else
            result.errors << "Line #{line}: #{page.errors.full_messages.to_sentence}"
          end
        else
          result.unchanged += 1
        end
      rescue ArgumentError => e
        result.errors << "Line #{line}: #{e.message}"
      end

      result
    rescue CSV::MalformedCSVError => e
      result.errors << e.message
      result
    end

    # Same layout import_csv reads, so an export can be edited and imported
    # back.
    def to_csv(pages = order(url: :asc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        pages.each.with_index(1) do |page, number|
          csv << [number, page.url, page.last_modified_at&.utc&.iso8601(3), page.indexed ? "Yes" : nil]
        end
      end
    end

    private

    def parse_time(value)
      value.presence && Time.iso8601(value.strip)
    rescue ArgumentError
      raise ArgumentError, "invalid Last modified #{value.inspect} (expected ISO 8601, e.g. 2026-07-05T12:07:01.000Z)"
    end

    def indexed_status?(value)
      %w[yes y true 1].include?(value.to_s.strip.downcase)
    end
  end

  private

  def url_must_be_http
    return if url.blank?

    uri = URI.parse(url)
    errors.add(:url, "must be an http(s) URL") unless uri.is_a?(URI::HTTP) && uri.host.present?
  rescue URI::InvalidURIError # includes URLs containing whitespace
    errors.add(:url, "must be an http(s) URL")
  end

  # Required, but not via presence: Mongoid turns unparseable input into nil
  # too, and only the raw value tells "left blank" from "mistyped", so just
  # one message shows. A future date can only be a mistake.
  def last_modified_at_must_be_valid_past_time
    if last_modified_at.nil?
      errors.add(:last_modified_at, last_modified_at_before_type_cast.present? ? "is not a valid date and time" : :blank)
    elsif last_modified_at > 1.minute.from_now # allow for clock skew
      errors.add(:last_modified_at, "can't be in the future")
    end
  end
end
