# encoding: UTF-8

module Google
  # A service account, so Search Console and Analytics data can be pulled
  # with no one signing in. The JWT is signed here rather than
  # through the googleauth gem, which would pull in a dozen dependencies for
  # two requests.
  class ApiClient
    TOKEN_URL = "https://oauth2.googleapis.com/token"
    TOKEN_LIFETIME = 1.hour
    # Refreshed a little early, so a token can't expire mid-sync.
    TOKEN_EXPIRY_MARGIN = 1.minute
    OPEN_TIMEOUT = 5
    READ_TIMEOUT = 60
    # The network here drops Google for seconds at a time, and a connection
    # that never opened never reached Google, so trying again can't repeat
    # anything.
    CONNECT_RETRY_PAUSE = 1
    NOT_CONFIGURED = "Google service account not configured (credentials google.client_email, google.private_key)"

    # One error for every kind of failure, carrying Google's own explanation
    # because it names the fix ("User does not have sufficient permission for
    # site ...").
    class Error < StandardError; end

    # Timeouts are adjustable because a sync can wait on a slow report but a
    # login can't.
    # A failed connection is retried unless turned off, since a caller that
    # can't wait would rather give up at once.
    def initialize(scope:, **options)
      options.assert_valid_keys(:client_email, :private_key, :cache, :connection, :open_timeout, :read_timeout, :retry_connect)
      @scope = scope
      @open_timeout = options.fetch(:open_timeout, OPEN_TIMEOUT)
      @read_timeout = options.fetch(:read_timeout, READ_TIMEOUT)
      @retry_connect = options.fetch(:retry_connect, true)
      @client_email = options.fetch(:client_email) { config[:client_email] }
      @private_key = options.fetch(:private_key) { config[:private_key] }
      @cache = options.fetch(:cache) { Rails.cache }
      @connection = options[:connection]
    end

    def configured?
      @client_email.present? && @private_key.present?
    end

    def get(url, params = nil)
      request { connection.get(url, params, "Authorization" => "Bearer #{access_token}") }
    end

    def post(url, body)
      request do
        connection.post(url, body.to_json, "Authorization" => "Bearer #{access_token}", "Content-Type" => "application/json")
      end
    end

    # Some writes answer with an empty body, so there's nothing to parse.
    def put(url)
      retrying_connect { connection.put(url, nil, "Authorization" => "Bearer #{access_token}") }
      nil
    rescue Faraday::Error => e
      raise Error, error_message(e)
    end

    private

    def request(&block)
      JSON.parse(retrying_connect(&block).body)
    rescue Faraday::Error, JSON::ParserError => e
      raise Error, error_message(e)
    end

    # Once only, so a real outage still fails within seconds.
    def retrying_connect
      yield
    rescue Faraday::ConnectionFailed
      raise unless @retry_connect

      sleep CONNECT_RETRY_PAUSE
      yield
    end

    def access_token
      @cache.fetch("google/access_token/#{@client_email}/#{@scope}", expires_in: TOKEN_LIFETIME - TOKEN_EXPIRY_MARGIN) do
        response = retrying_connect do
          connection.post(TOKEN_URL, URI.encode_www_form(
            grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
            assertion: assertion
          ), "Content-Type" => "application/x-www-form-urlencoded")
        end
        JSON.parse(response.body).fetch("access_token")
      end
    rescue Faraday::Error, JSON::ParserError, KeyError => e
      raise Error, "Couldn't get a Google access token: #{error_message(e)}"
    end

    def assertion
      now = Time.now.to_i
      header = {alg: "RS256", typ: "JWT"}
      claims = {iss: @client_email, scope: @scope, aud: TOKEN_URL, iat: now, exp: now + TOKEN_LIFETIME.to_i}
      signing_input = [header, claims].map { |part| Base64.urlsafe_encode64(part.to_json, padding: false) }.join(".")
      "#{signing_input}.#{Base64.urlsafe_encode64(signing_key.sign("SHA256", signing_input), padding: false)}"
    end

    # The key is pasted from the downloaded JSON file, where line breaks are
    # written as "\n"; YAML only turns those into real ones inside double
    # quotes, so both forms are accepted.
    def signing_key
      OpenSSL::PKey::RSA.new(@private_key.gsub("\\n", "\n"))
    rescue OpenSSL::PKey::PKeyError
      raise Error, "The Google private key in credentials isn't a valid PEM key"
    end

    # Google explains a refusal in the response body; the status line alone
    # says only "403". APIs nest it under "error"; the token endpoint, being
    # plain OAuth, puts it in "error_description".
    def error_message(error)
      details = JSON.parse(error.response_body.to_s) if error.respond_to?(:response_body)
      return error.message unless details.is_a?(Hash)

      nested = details["error"]
      (nested.is_a?(Hash) ? nested["message"] : details["error_description"] || nested).presence || error.message
    rescue JSON::ParserError
      error.message
    end

    def connection
      @connection ||= Faraday.new(
        headers: {"Accept" => "application/json", "User-Agent" => "harshal-ladhe-backend google sync"},
        # Flat, so a repeated parameter (Cloud Monitoring's groupByFields)
        # goes as Google expects rather than with Rails-style brackets.
        request: {open_timeout: @open_timeout, timeout: @read_timeout, params_encoder: Faraday::FlatParamsEncoder}
      ) do |faraday|
        faraday.use ExternalCallRecorder
        faraday.response :raise_error
      end
    end

    def config
      Rails.application.credentials.google || {}
    end
  end
end
