# encoding: UTF-8

module Google
  # An API key rather than the service account's token, since what Google's
  # public-data APIs return isn't the site owner's to grant.
  #
  # Setup: in the service account's Google Cloud project, enable each API
  # used (APIs & Services → Library), then APIs & Services → Credentials →
  # Create credentials → API key, restricted to those APIs. Save it as
  # `google.api_key` in the credentials.
  class KeyClient
    OPEN_TIMEOUT = 5
    # A PageSpeed run loads the page in a real browser, which can take most
    # of a minute.
    READ_TIMEOUT = 90
    NOT_CONFIGURED = "Google API key not configured (credentials google.api_key)"

    # Kept apart from the service account's errors, since a refusal here
    # means the key, not the account.
    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    # `connection` is injectable so specs never call Google.
    # Unknown keys raise, so a misspelt option fails loudly instead of quietly
    # falling back to its default.
    def initialize(options = {})
      options.assert_valid_keys(:api_key, :connection, :read_timeout)
      @api_key = options.fetch(:api_key) { Rails.application.credentials.dig(:google, :api_key) }
      @connection = options[:connection]
      @read_timeout = options.fetch(:read_timeout, READ_TIMEOUT)
    end

    def configured?
      @api_key.present?
    end

    def get(url, params = {})
      request { connection.get(url, params.merge(key: @api_key)) }
    end

    def post(url, body)
      request do
        connection.post("#{url}?#{URI.encode_www_form(key: @api_key)}", body.to_json, "Content-Type" => "application/json")
      end
    end

    private

    def request(&block)
      JSON.parse(retrying_connect(&block).body)
    rescue Faraday::Error => e
      raise Error.new(error_message(e), status: e.response_status)
    rescue JSON::ParserError => e
      raise Error, e.message
    end

    # Once only, for the same reason as the service account's client.
    def retrying_connect
      yield
    rescue Faraday::ConnectionFailed
      sleep ApiClient::CONNECT_RETRY_PAUSE
      yield
    end

    # Google explains a refusal in the body ("API key not valid", "Quota
    # exceeded"); the status line alone says only "400".
    def error_message(error)
      details = JSON.parse(error.response_body.to_s)
      (details.dig("error", "message") if details.is_a?(Hash)).presence || error.message
    rescue JSON::ParserError
      error.message
    end

    def connection
      @connection ||= Faraday.new(
        headers: {"Accept" => "application/json", "User-Agent" => "harshal-ladhe-backend google sync"},
        # Flat, so a repeated parameter (PageSpeed's category) goes as
        # category=A&category=B rather than category[]=A.
        request: {open_timeout: OPEN_TIMEOUT, timeout: @read_timeout, params_encoder: Faraday::FlatParamsEncoder}
      ) do |faraday|
        faraday.use ExternalCallRecorder
        faraday.response :raise_error
      end
    end
  end
end
