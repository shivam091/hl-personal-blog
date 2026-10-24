# encoding: UTF-8

require "active_support/core_ext/integer/time"

Rails.application.configure do
  config.enable_reloading = false

  config.eager_load = true

  config.consider_all_requests_local = false

  config.action_controller.perform_caching = true

  # Far-future expiry is safe because asset filenames carry a digest.
  config.public_file_server.headers = {"cache-control" => "public, max-age=#{1.year.to_i}"}

  config.log_tags = [:request_id]
  config.logger   = ActiveSupport::TaggedLogging.logger(STDOUT)

  # Not debug by default, since that logs personally identifiable information.
  config.log_level = ENV.fetch("RAILS_LOG_LEVEL", "info")

  # So health checks don't clog the logs.
  config.silence_healthcheck_path = "/up"

  config.active_support.report_deprecations = false

  # In-process cache; nothing here needs to survive a restart.
  config.cache_store = :memory_store

  # Jobs run in-process (Active Job's :async adapter); there's no job queue.
  config.active_job.queue_adapter = :async

  # Mail linking back to the admin is sent from GitHub Actions, which can't
  # know the app's address, so it's given one.
  admin_url = URI.parse(ENV["ADMIN_URL"].presence || "https://example.com")
  config.action_mailer.default_url_options = {host: admin_url.host, port: admin_url.port, protocol: admin_url.scheme}

  config.i18n.fallbacks = true
end
