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
    OPEN_TIMEOUT = 5
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
      options.assert_valid_keys(:project_id, :username, :secret, :host, :connection)
      credentials = Rails.application.credentials.mixpanel || {}
      @project_id = options.fetch(:project_id) { credentials[:project_id] }
      @username = options.fetch(:username) { credentials[:service_account_username] }
      @secret = options.fetch(:secret) { credentials[:service_account_secret] }
      @host = options.fetch(:host) { credentials[:data_host].presence || DEFAULT_HOST }
      @connection = options[:connection]
    end

    def configured?
      [@project_id, @username, @secret].all?(&:present?)
    end

    # One day per call, so each event belongs to the day asked for in the
    # project's own time zone, whatever its timestamps say.
    def export(date)
      body = retrying_connect do
        connection.get(EXPORT_PATH, project_id: @project_id, from_date: date.iso8601, to_date: date.iso8601).body
      end
      body.to_s.each_line.filter_map { |line| JSON.parse(line) if line.strip.present? }
    rescue Faraday::Error => e
      raise Error.new(error_message(e), status: e.response_status)
    rescue JSON::ParserError => e
      raise Error, "Mixpanel sent an unreadable export: #{e.message}"
    end

    private

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
      @connection ||= Faraday.new(
        url: "https://#{@host}",
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
