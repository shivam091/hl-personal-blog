# encoding: UTF-8

module Mixpanel
  # The raw export rather than the Query API, since it returns every event
  # with all its properties and costs one of the project's 60 hourly queries
  # for a whole day, where a report a query would spend them quickly.
  class Client
    EXPORT_PATH = "/api/2.0/export"
    # The US host; a project kept in EU or India residency is read from
    # data-eu.mixpanel.com or data-in.mixpanel.com instead.
    DEFAULT_HOST = "data.mixpanel.com"
    # Annotations, Lexicon and the Query API live on the app's own host in
    # the same region as the export.
    APP_HOSTS = {"data.mixpanel.com" => "mixpanel.com", "data-eu.mixpanel.com" => "eu.mixpanel.com", "data-in.mixpanel.com" => "in.mixpanel.com"}.freeze
    # Mixpanel's US hosts have taken over 5 seconds to accept a connection
    # from some networks.
    OPEN_TIMEOUT = 15
    # Mixpanel's whole reply when the export is asked of a region the
    # project isn't kept in, sent with a 200.
    TERMINATED = "terminated early"
    # Mixpanel streams the day as it reads it, which for a busy day takes a while.
    READ_TIMEOUT = 120
    NOT_CONFIGURED = "Mixpanel not configured (credentials mixpanel.project_id, service_account_username, service_account_secret)"

    class Error < StandardError
      attr_reader :status

      def initialize(message, status: nil)
        super(message)
        @status = status
      end
    end

    def initialize(options = {})
      options.assert_valid_keys(:project_id, :username, :secret, :host, :connection, :app_connection)
      credentials = Rails.application.credentials.mixpanel || {}
      @project_id = options.fetch(:project_id) { credentials[:project_id] }
      @username = options.fetch(:username) { credentials[:service_account_username] }
      @secret = options.fetch(:secret) { credentials[:service_account_secret] }
      @host = options.fetch(:host) { credentials[:data_host].presence || DEFAULT_HOST }
      @connection = options[:connection]
      @app_connection = options[:app_connection]
    end

    attr_reader :project_id

    def configured?
      [@project_id, @username, @secret].all?(&:present?)
    end

    # One day per call, so each event belongs to the day asked for in the
    # project's own time zone, whatever its timestamps say.
    def export(date)
      body = retrying_connect do
        connection.get(EXPORT_PATH, project_id: @project_id, from_date: date.iso8601, to_date: date.iso8601).body
      end
      if body.to_s.strip == TERMINATED
        raise Error, "Mixpanel cut the export short (#{TERMINATED.inspect}), which it does when data_host is another region than the project's " \
          "(credentials mixpanel.data_host: data.mixpanel.com for US, data-eu or data-in for EU or India)"
      end

      body.to_s.each_line.filter_map { |line| JSON.parse(line) if line.strip.present? }
    rescue Faraday::Error => e
      raise Error.new(error_message(e), status: e.response_status)
    rescue JSON::ParserError => e
      raise Error, "Mixpanel sent an unreadable export: #{e.message}"
    end

    # The app API (annotations, Lexicon), under the project's own path.
    def app_get(path, params = {})
      app_request { app_connection.get("/api/app/projects/#{@project_id}/#{path}", params) }
    end

    def app_post(path, body)
      app_request { app_connection.post("/api/app/projects/#{@project_id}/#{path}", body.to_json, "Content-Type" => "application/json") }
    end

    # The Query API, which names the project in the query rather than the path.
    def query(path, params = {})
      app_request { app_connection.get("/api/query/#{path}", params.merge(project_id: @project_id)) }
    end

    private

    def app_request(&block)
      JSON.parse(retrying_connect(&block).body.presence || "{}")
    rescue Faraday::Error => e
      raise Error.new(error_message(e), status: e.response_status)
    rescue JSON::ParserError => e
      raise Error, "Mixpanel sent an unreadable reply: #{e.message}"
    end

    # Once only, as for Google's clients: a dropped connection is usually
    # momentary, and a second failure is worth reporting.
    def retrying_connect
      yield
    rescue Faraday::ConnectionFailed
      sleep Google::ApiClient::CONNECT_RETRY_PAUSE
      yield
    end

    # Mixpanel explains a refusal in the body ("Invalid credentials",
    # "rate limit exceeded"); the status line alone says only "400".
    def error_message(error)
      body = error.response_body.to_s
      details = JSON.parse(body)
      (details["error"] if details.is_a?(Hash)).presence || error.message
    rescue JSON::ParserError
      body.presence&.truncate(200) || error.message
    end

    def connection
      @connection ||= build_connection(@host)
    end

    def app_connection
      @app_connection ||= build_connection(APP_HOSTS.fetch(@host, "mixpanel.com"))
    end

    def build_connection(host)
      Faraday.new(
        url: "https://#{host}",
        headers: {"Accept" => "application/json", "User-Agent" => "harshal-ladhe-backend mixpanel sync"},
        request: {open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT}
      ) do |faraday|
        faraday.request :authorization, :basic, @username, @secret
        faraday.use ExternalCallRecorder, service: "Mixpanel"
        faraday.response :raise_error
      end
    end
  end
end
