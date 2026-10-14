# encoding: UTF-8

require "csv"

class CrawledPage
  include Mongoid::Document
  include Mongoid::Timestamps
  include StripAttribute

  CSV_HEADERS = ["#", "URL", "Last modified", "Status"].freeze

  field :url, type: String
  field :last_modified_at, type: Time
  field :indexed, type: Boolean, default: false
  # So a request is followed until an inspection finds the page indexed.
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
    def to_csv(pages = order(url: :asc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        pages.each.with_index(1) do |page, number|
          csv << [number, page.url, page.last_modified_at&.utc&.iso8601(3), page.indexed ? "Yes" : nil]
        end
      end
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
