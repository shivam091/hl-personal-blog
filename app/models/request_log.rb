# encoding: UTF-8

require "csv"

# Keyed by the request id, which also appears in the Rails log lines, so a
# log entry and its log lines can be matched up.
class RequestLog
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include UpcaseAttribute

  CSV_HEADERS = [
    "Request ID", "Time", "Method", "URL", "Status", "Duration (ms)", "Response size (bytes)",
    "IP", "Country", "City", "Organization", "User agent", "Referrer", "User", "Exception"
  ].freeze

  field :_id, type: String, overwrite: true, default: -> { SecureRandom.uuid }
  field :uri, type: String
  field :request_method, type: String
  field :query_params, type: Hash, default: {}
  field :session_id, type: String
  field :session_private_id, type: String
  field :remote_address, type: String
  field :user_agent, type: String
  field :referrer, type: String
  field :origin, type: String
  field :user, type: String
  field :memory_usage, type: Integer, default: 0
  field :cpu_usage, type: Float, default: 0.0
  field :ip_info, type: Hash, default: {}
  field :request_headers, type: Hash, default: {}
  field :response_headers, type: Hash, default: {}
  field :status, type: Integer
  field :response_size, type: Integer
  field :exception, type: Hash, default: {}
  field :elapsed_time, type: Float, default: 0.0

  # Development shares the live database, so its logs land next to
  # production's and need telling apart. Matched on the URL's host rather than
  # the client IP, because the hosting platform's own health probes also reach
  # production from a loopback address.
  LOCAL_URI = %r{\Ahttps?://(localhost|127\.0\.0\.1|\[::1\])(:\d+)?(?=[/?#]|\z)}i

  alias_attribute :uuid, :_id

  scope :local, -> { where(uri: LOCAL_URI) }

  # Sorts carry an _id tiebreaker, which an index without it can't serve.
  index({created_at: -1, _id: 1})
  index({status: 1})
  index({elapsed_time: -1, _id: 1})

  upcase_attributes! :request_method

  validates :uri, :request_method, :status, presence: true

  def to_s
    "#{request_method} #{path}"
  end

  def path
    URI.parse(uri.to_s).request_uri
  rescue URI::InvalidURIError
    uri
  end

  def elapsed_ms
    elapsed_time.to_f * 1000
  end

  def error?
    exception.present? && exception["class"].present?
  end

  class << self
    def to_csv(logs = order(created_at: :desc))
      CSV.generate do |csv|
        csv << CSV_HEADERS
        logs.each do |log|
          info = log.ip_info || {}
          csv << [
            log.uuid,
            log.created_at&.utc&.iso8601(3),
            log.request_method,
            log.uri,
            log.status,
            log.elapsed_ms.round(1),
            log.response_size,
            log.remote_address,
            info["country"],
            info["city"],
            (info["org"] || info["as_name"]),
            log.user_agent,
            log.referrer,
            log.user,
            log.exception&.values_at("class", "message")&.compact&.join(": ").presence
          ]
        end
      end
    end
  end
end
