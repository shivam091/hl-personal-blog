# encoding: UTF-8

# Exists because an IP alone doesn't say where a client is or who owns it,
# which is what tells real visitors from bots and data centres. Cached per IP
# because the same few clients make most requests and the API is metered.
class IpInfoService
  CACHE_TTL = 1.day
  # A failing API shouldn't be retried on every request while it's down.
  FAILURE_CACHE_TTL = 5.minutes
  # Short, since the lookup holds up the Puma thread logging the request.
  OPEN_TIMEOUT = 1
  READ_TIMEOUT = 2

  class << self
    def lookup(ip)
      new.lookup(ip)
    end
  end

  # `connection` is injectable so specs never call the real, metered API.
  def initialize(token: config[:token], endpoints: config[:endpoints], cache: Rails.cache, connection: nil)
    @token = token
    @endpoints = Array(endpoints)
    @cache = cache
    @connection = connection
  end

  # Local, private, and malformed addresses are skipped: the API knows
  # nothing about them and each call would waste quota.
  def lookup(ip)
    return if @token.blank? || @endpoints.empty? || !public_ip?(ip)

    @cache.fetch("ipinfo/#{ip}", expires_in: CACHE_TTL) { fetch(ip) }
  rescue Faraday::Error, JSON::ParserError => e
    Rails.logger.warn("IP lookup failed for #{ip}: #{e.message}")
    {"ip" => ip, "error" => e.message}.tap do |failure|
      @cache.write("ipinfo/#{ip}", failure, expires_in: FAILURE_CACHE_TTL)
    end
  end

  private

  # Each endpoint knows different things about the IP on the free plan, so
  # merging them gives the fullest picture.
  def fetch(ip)
    @endpoints.reduce({}) do |details, endpoint|
      response = connection.get(format(endpoint, ip: ip))
      details.merge(JSON.parse(response.body).except("readme"))
    end
  end

  def connection
    @connection ||= Faraday.new(
      headers: {"Authorization" => "Bearer #{@token}", "Accept" => "application/json"},
      request: {open_timeout: OPEN_TIMEOUT, timeout: READ_TIMEOUT}
    ) do |faraday|
      faraday.use ExternalCallRecorder, service: "IP lookup"
      faraday.response :raise_error
    end
  end

  def public_ip?(ip)
    address = IPAddr.new(ip.to_s)
    !(address.private? || address.loopback? || address.link_local?)
  rescue IPAddr::Error
    false
  end

  def config
    Rails.application.credentials.ipinfo || {}
  end
end
