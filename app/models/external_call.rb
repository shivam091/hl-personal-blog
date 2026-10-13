# encoding: UTF-8

# A slow or refused call to Google, the blog's feed and sitemap or an IP lookup
# would otherwise leave at most a log line. Kept so what was asked of whom, and
# how it went, can be reviewed afterwards.
class ExternalCall
  include Mongoid::Document
  include Mongoid::Timestamps::Created
  include UpcaseAttribute

  # One Google client serves many APIs, so they're told apart by host and
  # path. First match wins, so narrower prefixes come first.
  SERVICES = {
    "oauth2.googleapis.com" => "Google sign-in",
    "searchconsole.googleapis.com" => "Search Console",
    "analyticsdata.googleapis.com" => "Google Analytics",
    "analyticsadmin.googleapis.com" => "Google Analytics",
    "www.googleapis.com/pagespeedonline" => "PageSpeed Insights",
    "chromeuxreport.googleapis.com" => "Chrome UX Report",
    "safebrowsing.googleapis.com" => "Safe Browsing",
    "recaptchaenterprise.googleapis.com" => "reCAPTCHA",
    "www.google.com/recaptcha" => "reCAPTCHA"
  }.freeze
  # Credentials can ride in the query string, and a stored URL is shown to
  # anyone who can open the admin.
  SECRET_PARAMS = %w[key token access_token secret api_key].freeze
  FILTERED = "[FILTERED]"
  # Enough to hold Google's explanation of a refusal without storing a page.
  MAX_ERROR_BODY = 1_000

  field :service, type: String
  field :http_method, type: String
  field :url, type: String
  field :host, type: String
  # Nil when no response came back, as on a timeout.
  field :status, type: Integer
  field :duration_ms, type: Float
  field :response_size, type: Integer
  field :error, type: String
  field :error_body, type: String

  # Sorts carry an _id tiebreaker, which an index without it can't serve.
  index({created_at: -1, _id: 1})
  index({service: 1, created_at: -1})
  index({duration_ms: -1, _id: 1})

  upcase_attributes! :http_method

  validates :service, :http_method, :url, presence: true

  def to_s
    "#{http_method} #{service}"
  end

  def failed?
    status.nil? || status >= 400
  end

  class << self
    # Recording must never be why a call fails, so a write error is only logged.
    def record(service:, http_method:, url:, **attributes)
      url = redact(url.to_s)
      create!(service: service || service_for(url), http_method: http_method, url: url, host: URI.parse(url).host, **attributes)
    rescue StandardError => e
      Rails.logger.warn("Couldn't record the external call to #{url}: #{e.class}: #{e.message}")
      nil
    end

    def service_for(url)
      uri = URI.parse(url.to_s)
      address = "#{uri.host}#{uri.path}"
      SERVICES.find { |prefix, _| address.start_with?(prefix) }&.last || uri.host
    rescue URI::InvalidURIError
      url
    end

    def services
      (SERVICES.values + distinct(:service)).compact.uniq.sort
    end

    def redact(url)
      uri = URI.parse(url)
      return url if uri.query.blank?

      params = URI.decode_www_form(uri.query).map { |name, value| [name, SECRET_PARAMS.include?(name.downcase) ? FILTERED : value] }
      uri.query = URI.encode_www_form(params)
      uri.to_s
    rescue URI::InvalidURIError, ArgumentError
      url
    end
  end
end
