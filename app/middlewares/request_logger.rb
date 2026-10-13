# encoding: UTF-8

# Logging never delays the client or breaks the request.
class RequestLogger
  # Lets logs say who made the request without the middleware knowing how
  # signing in works.
  USER_ENV_KEY = "request_logger.user"

  # Health checks and assets are frequent and say nothing about usage.
  SKIPPED_PATHS = %w[/up /assets/ /icon.png /icon.svg /favicon.ico].freeze

  # Credentials and cookies must never end up in the logs.
  FILTERED_REQUEST_HEADERS = %w[Authorization Proxy-Authorization Cookie X-Csrf-Token].freeze
  FILTERED_RESPONSE_HEADERS = %w[set-cookie].freeze

  BACKTRACE_LINES = 10

  class << self
    def skip?(env)
      path = env["PATH_INFO"].to_s
      SKIPPED_PATHS.any? { |skipped| skipped.end_with?("/") ? path.start_with?(skipped) : path == skipped }
    end
  end

  def initialize(app)
    @app = app
  end

  def call(env)
    return @app.call(env) if self.class.skip?(env)

    started = clock
    status, headers, body = @app.call(env)
    counted = Body.new(body) { log(env, started, status: status, headers: headers, bytesize: counted.bytesize) }
    [status, headers, counted]
  rescue Exception => exception # rubocop:disable Lint/RescueException -- logged, then re-raised untouched
    log(env, started, exception: exception) if started
    raise
  end

  # The logged size must be what the client actually received, measured
  # without changing how the server is able to read the body.
  class Body < Rack::BodyProxy
    attr_reader :bytesize

    def method_missing(name, *args, &block)
      case name
      when :each
        @bytesize = 0
        @body.each do |chunk|
          @bytesize += chunk.bytesize
          block.call(chunk)
        end
      when :to_ary
        begin
          @body.to_ary.tap { |chunks| @bytesize = chunks.sum(&:bytesize) }
        ensure
          close
        end
      else
        super
      end
    end
  end

  private

  def log(env, started, status: nil, headers: {}, bytesize: nil, exception: nil)
    request = ActionDispatch::Request.new(env)
    elapsed = clock.zip(started).map { |now, start| now - start }
    exception ||= env["action_dispatch.exception"]
    session = request.session if request.session.respond_to?(:id)

    RequestLog.create!(
      uuid: request.uuid,
      uri: request.original_url,
      request_method: request.request_method,
      query_params: serializable(request.filtered_parameters.except("controller", "action")),
      session_id: session&.id&.public_id,
      session_private_id: session&.id&.private_id,
      remote_address: request.remote_ip,
      user_agent: request.user_agent,
      referrer: request.referrer,
      origin: request.origin,
      user: env[USER_ENV_KEY],
      ip_info: IpInfoService.lookup(request.remote_ip),
      request_headers: request_headers(env),
      response_headers: headers.to_h.except(*FILTERED_RESPONSE_HEADERS),
      status: status || ActionDispatch::ExceptionWrapper.status_code_for_exception(exception.class.name),
      response_size: bytesize || headers["content-length"]&.to_i,
      exception: exception_details(exception),
      elapsed_time: elapsed.first.round(4),
      cpu_usage: cpu_usage(*elapsed),
      memory_usage: memory_usage
    )
  rescue StandardError => e
    Rails.logger.error("Failed to log request #{env["action_dispatch.request_id"]}: #{e.class}: #{e.message}")
  end

  # Wall-clock and this thread's CPU time, so CPU share is per request rather
  # than the process's lifetime average.
  def clock
    [Process.clock_gettime(Process::CLOCK_MONOTONIC), Process.clock_gettime(Process::CLOCK_THREAD_CPUTIME_ID)]
  end

  def cpu_usage(wall, cpu)
    return 0.0 unless wall.positive?

    (cpu / wall * 100).clamp(0, 100).round(2)
  end

  # Read from /proc because forking `ps` on every request would cost more
  # than the request itself.
  def memory_usage
    File.foreach("/proc/self/status") { |line| return line.split[1].to_i if line.start_with?("VmRSS:") }
    0
  rescue Errno::ENOENT
    # No /proc on this platform (e.g. macOS), so fall back to ps.
    `ps -o rss= -p #{Process.pid}`.to_i
  end

  def request_headers(env)
    env.filter_map do |key, value|
      name = key.delete_prefix("HTTP_") if key.start_with?("HTTP_") || %w[CONTENT_TYPE CONTENT_LENGTH].include?(key)
      [name.split("_").map(&:capitalize).join("-"), value.to_s] if name
    end.to_h.except(*FILTERED_REQUEST_HEADERS)
  end

  def exception_details(exception)
    return {} unless exception

    {
      "class" => exception.class.name,
      "message" => exception.message,
      "backtrace" => Rails.backtrace_cleaner.clean(Array(exception.backtrace)).first(BACKTRACE_LINES)
    }
  end

  # Params can hold objects MongoDB can't store.
  def serializable(value)
    case value
    when Hash
      value.to_h { |key, nested| [key.to_s, serializable(nested)] }
    when Array
      value.map { |nested| serializable(nested) }
    when String, Numeric, true, false, nil
      value
    else
      value.to_s
    end
  end
end
