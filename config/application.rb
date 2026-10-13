# encoding: UTF-8

require_relative "boot"

require "rails"
# Active Record, the frameworks built on it (Active Storage, Action Text,
# Action Mailbox), and Action Cable are left out because all data lives in
# MongoDB.
require "active_model/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_view/railtie"

Bundler.require(*Rails.groups)

require_relative "../app/middlewares/request_logger"

module HLPersonalBlog
  class Application < Rails::Application
    config.load_defaults 8.1

    # Rake tasks and assets hold no constants to autoload.
    config.autoload_lib(ignore: %w[assets tasks])

    # Middleware is built into the stack once at boot, so it's required above
    # rather than autoloaded, and can't be reloaded.
    Rails.autoloaders.main.ignore(Rails.root.join("app/middlewares"))

    # Last in the stack, so the logger sees the session, the signed-in admin,
    # and exceptions before ShowExceptions turns them into error pages.
    config.middleware.use RequestLogger

    # The admin works in India, so times are shown, and days for date
    # filters are counted, in IST. MongoDB still stores UTC.
    config.time_zone = "Asia/Kolkata"

    # Objects name their own shared partials, which must resolve the same
    # from a namespaced controller as from any other.
    config.action_view.prefix_partial_path_with_controller_namespace = false

    config.generators do |g|
      g.test_framework :rspec,
                       fixtures: false,
                       view_specs: false,
                       helper_specs: false,
                       routing_specs: false
    end
  end
end
