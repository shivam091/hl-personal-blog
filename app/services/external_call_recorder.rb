# encoding: UTF-8

# In each connection's own stack rather than as a global Faraday default, so
# specs that inject a stubbed connection never write records.
class ExternalCallRecorder < Faraday::Middleware
  # `service` names the caller when its host doesn't, as the blog's feed and
  # sitemap share one.
  def initialize(app, service: nil)
    super(app)
    @service = service
  end

  # Placed before `raise_error`, so a refusal is seen as the error it raises.
  def call(env)
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    response = @app.call(env)
    record(env, started, status: response.status, response_size: response.body.to_s.bytesize)
    response
  rescue Faraday::Error => e
    body = e.response_body.to_s if e.respond_to?(:response_body)
    record(env, started, status: e.response_status, response_size: body&.bytesize, error: e.message,
      error_body: body.presence&.truncate(ExternalCall::MAX_ERROR_BODY))
    raise
  end

  private

  def record(env, started, **attributes)
    ExternalCall.record(service: @service, http_method: env.method.to_s, url: env.url.to_s,
      duration_ms: (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started) * 1000, **attributes)
  end
end
